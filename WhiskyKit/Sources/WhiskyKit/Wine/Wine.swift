//
//  Wine.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import Darwin
import os.log

public class Wine {
    /// URL to the installed `DXVK` folder
    static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
    public static var wineBinary: URL {
        let wine64 = WhiskyWineInstaller.binFolder.appending(path: "wine64")
        if FileManager.default.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return WhiskyWineInstaller.binFolder.appending(path: "wine")
    }
    private static var wineserverBinary: URL {
        WhiskyWineInstaller.binFolder.appending(path: "wineserver")
    }

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?,
        qualityOfService: QualityOfService = .userInitiated,
        quiet: Bool = false,
        systemLog: Bool = true,
        fileCaptureOnly: Bool = false
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = qualityOfService

        return try process.runStream(
            name: name ?? args.joined(separator: " "),
            fileHandle: fileHandle,
            quiet: quiet,
            systemLog: systemLog,
            fileCaptureOnly: fileCaptureOnly
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?,
        qualityOfService: QualityOfService = .userInitiated,
        quiet: Bool = false,
        systemLog: Bool = true,
        fileCaptureOnly: Bool = false,
        engine: (any WineEngine)? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment,
            executableURL: engine?.wineBinary ?? wineBinary,
            fileHandle: fileHandle,
            qualityOfService: qualityOfService,
            quiet: quiet,
            systemLog: systemLog,
            fileCaptureOnly: fileCaptureOnly
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:],
        executableURL: URL? = nil,
        qualityOfService: QualityOfService = .userInitiated,
        quiet: Bool = false,
        logFileHandle: FileHandle? = nil,
        systemLog: Bool = true,
        fileCaptureOnly: Bool = false,
        engine: (any WineEngine)? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle: FileHandle?
        if let logFileHandle {
            fileHandle = logFileHandle
        } else if quiet || fileCaptureOnly {
            fileHandle = nil
        } else {
            fileHandle = try makeFileHandle()
            fileHandle?.writeApplicationInfo()
            if let fileHandle {
                fileHandle.writeInfo(for: bottle)
            }
        }

        do {
            return try runWineProcess(
                name: name, args: args,
                environment: constructWineEnvironment(
                    for: bottle,
                    environment: environment,
                    executableURL: executableURL
                ),
                fileHandle: fileHandle,
                qualityOfService: qualityOfService,
                quiet: quiet,
                systemLog: systemLog,
                fileCaptureOnly: fileCaptureOnly && logFileHandle != nil,
                engine: engine
            )
        } catch {
            try? fileHandle?.close()
            throw error
        }
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        do {
            return try runWineserverProcess(
                name: name, args: args,
                environment: constructWineServerEnvironment(for: bottle, environment: environment),
                fileHandle: fileHandle
            )
        } catch {
            try? fileHandle.close()
            throw error
        }
    }

    public static func prewarmBottle(_ bottle: Bottle) async throws {
        let gate = await MainActor.run { () -> String in
            if ProgramLaunchCoordinator.shared.isWarm(bottle: bottle) {
                return "warm"
            }
            if ProgramLaunchCoordinator.shared.isWarming(bottle: bottle) {
                return "warming"
            }
            ProgramLaunchCoordinator.shared.beginWarmup(bottle: bottle)
            return "start"
        }

        if gate == "warm" {
            return
        }
        if gate == "warming" {
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(40))
                let done = await MainActor.run {
                    ProgramLaunchCoordinator.shared.isWarm(bottle: bottle)
                        || !ProgramLaunchCoordinator.shared.isWarming(bottle: bottle)
                }
                if done {
                    return
                }
            }
            return
        }

        // ZeroPath: the readiness oracle can prove the prefix is
        // boot-complete from on-disk evidence alone. When it does, the
        // "prewarm" is genuinely instant — nothing to spawn at all.
        let bottleKey = ProgramRunLogStore.bottleKey(for: bottle)
        let engine = WineEngineRegistry.shared.current
        let engineBuildID = "\(engine.identifier)-\(engine.installedVersion()?.description ?? "unknown")"
        let baseline = PrefixReadinessOracle.loadBaseline(bottleKey: bottleKey)
        let verdict = PrefixReadinessOracle.verdict(
            bottleURL: bottle.url,
            saved: baseline,
            engineBuildID: engineBuildID
        )
        if verdict.isReady {
            Logger.wineKit.info("ZeroPath: prewarm skipped (readiness proven)")
            await MainActor.run {
                ProgramLaunchCoordinator.shared.markWarm(bottle: bottle)
            }
            return
        }

        do {
            let process = Process()
            process.executableURL = wineserverBinary
            process.arguments = ["-p"]
            process.environment = constructWineServerEnvironment(for: bottle)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.qualityOfService = .utility
            try process.run()
            BottleProcessRegistry.shared.register(process, bottle: bottle)

            try await Task.sleep(for: .milliseconds(150))
            let success = process.isRunning || process.terminationStatus == 0
            await MainActor.run {
                ProgramLaunchCoordinator.shared.finishWarmup(bottle: bottle, success: success)
            }
        } catch {
            await MainActor.run {
                ProgramLaunchCoordinator.shared.finishWarmup(bottle: bottle, success: false)
            }
            throw error
        }
    }

    public static func ensureBottleReady(_ bottle: Bottle) async {
        do {
            try await prewarmBottle(bottle)
        } catch {
            Logger.wineKit.warning(
                "Bottle prewarm skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public static func runProgram(
        at url: URL,
        args: [String] = [],
        bottle: Bottle,
        environment: [String: String] = [:],
        wait: Bool = true,
        applyDXVK: Bool = true,
        recipe: Recipe? = nil,
        autoSelectEngine: Bool = true,
        captureRunLog: Bool = true
    ) async throws {
        // Plan (PE scan, engine decision, readiness fingerprint) and
        // warmup (wineserver spawn) touch disjoint state; racing them
        // hides the warmup latency behind the planning work instead of
        // paying both serially.
        async let warmup: Void = ensureBottleReady(bottle)
        let launchContext = await planLaunch(
            url: url,
            bottle: bottle,
            recipe: recipe,
            applyDXVK: applyDXVK,
            autoSelectEngine: autoSelectEngine,
            environment: environment
        )
        await warmup
        defer {
            if autoSelectEngine {
                LaunchEnginePolicy.restoreUserSelection(for: launchContext.engineDecision)
            }
        }

        try await executeLaunch(
            url: url,
            args: args,
            bottle: bottle,
            environment: launchContext.resolvedEnvironment,
            wait: wait,
            applyDXVK: applyDXVK,
            recipe: recipe,
            autoSelectEngine: autoSelectEngine,
            captureRunLog: captureRunLog,
            context: launchContext
        )
    }

    struct ZeroPathLaunchContext {
        var engineDecision: LaunchEnginePolicy.AppliedLaunch?
        var launchEngine: any WineEngine
        var profile: RuntimeProfile
        var plan: DoubleLaunchPlan
        var bottleKey: String
        var engineBuildID: String
        var launchStart: Date
        var displayIntents: [WineIntentEnvelope]
        var resolvedEnvironment: [String: String]
    }

    // swiftlint:disable:next function_parameter_count
    private static func planLaunch(
        url: URL,
        bottle: Bottle,
        recipe: Recipe?,
        applyDXVK: Bool,
        autoSelectEngine: Bool,
        environment: [String: String]
    ) async -> ZeroPathLaunchContext {
        let engineDecision: LaunchEnginePolicy.AppliedLaunch?
        if autoSelectEngine {
            engineDecision = LaunchEnginePolicy.applyForLaunch(
                executable: url,
                recipe: recipe,
                bottleDXVKEnabled: bottle.settings.dxvk,
                bottleEngineID: bottle.settings.engineID
            )
        } else {
            engineDecision = nil
        }
        // Resolve the binaries synchronously from the applied engine:
        // the registry may be flipped by a concurrent launch or a UI
        // switch between here and spawn, and this launch must run under
        // exactly the engine that was selected for it.
        let launchEngine = engineDecision?.engine ?? WineEngineRegistry.shared.current

        let profile = RuntimeLaunchOptimizer.profile(forExecutableAt: url)

        var shouldApplyDXVK = applyDXVK
            && RuntimeLaunchOptimizer.effectiveDXVKEnabled(
                profile: profile,
                bottleDXVKEnabled: bottle.settings.dxvk
            )
        if engineDecision?.decision.engineID == WineEngineCatalog.d3dMetalIdentifier {
            shouldApplyDXVK = false
        } else if recipe?.renderer == .d3dmetal {
            shouldApplyDXVK = false
        } else if recipe?.renderer == .wined3d {
            shouldApplyDXVK = false
        }

        if shouldApplyDXVK {
            let dxvkReady = await MainActor.run {
                ProgramLaunchCoordinator.shared.isDXVKReady(bottle: bottle)
            }
            if !dxvkReady {
                try? enableDXVK(bottle: bottle)
                await MainActor.run {
                    ProgramLaunchCoordinator.shared.markDXVKReady(bottle: bottle)
                }
            }
        }

        var environment = environment
        if environment["WINEDLLOVERRIDES"]?.isEmpty == true {
            environment.removeValue(forKey: "WINEDLLOVERRIDES")
        }

        // ---- ZeroPath: predict prefix readiness, skip boot-check ----
        let launchStart = Date()
        let engineBuildID = "\(launchEngine.identifier)-\(launchEngine.installedVersion()?.description ?? "unknown")"
        let bottleKey = ProgramRunLogStore.bottleKey(for: bottle)
        let plan = DoubleLaunchExecutor.plan(
            bottle: bottle,
            fingerprintSaved: PrefixReadinessOracle.loadBaseline(bottleKey: bottleKey),
            engineBuildID: engineBuildID
        )
        var displayIntents: [WineIntentEnvelope] = []
        if plan.readinessSkipped {
            if profile == .classic32 {
                displayIntents = LaunchPathPreflight.applyClassic32(bottle: bottle)
            }
            Logger.wineKit.info("ZeroPath: readiness proven, launching directly")
        } else {
            await DisplayPolicy.apply(for: profile, bottle: bottle)
        }
        if plan.doubleLaunch {
            environment = DoubleLaunchExecutor.injecting(
                record: .init(doubleLaunch: true, readinessSkipped: false),
                into: environment
            )
        }
        // ---- Game Boost: per-program performance posture ----
        let programKey = ProgramRunLogStore.programKey(for: url)
        if let boost = GameBoostRegistry.profile(for: programKey) {
            // Overlay merges only keys the user did not set explicitly:
            // a hand-tuned variable on the program or bottle always wins.
            for (key, value) in boost.environmentOverlay() where environment[key] == nil {
                environment[key] = value
            }
            Logger.wineKit.info("GameBoost: \(boost.posture.rawValue) posture applied to \(url.lastPathComponent)")
        }
        // ---- end Game Boost ----

        let context = ZeroPathLaunchContext(
            engineDecision: engineDecision,
            launchEngine: launchEngine,
            profile: profile,
            plan: plan,
            bottleKey: bottleKey,
            engineBuildID: engineBuildID,
            launchStart: launchStart,
            displayIntents: displayIntents,
            resolvedEnvironment: environment
        )
        return context
    }

    // swiftlint:disable:next function_body_length function_parameter_count
    private static func executeLaunch(
        url: URL,
        args: [String],
        bottle: Bottle,
        environment: [String: String],
        wait: Bool,
        applyDXVK: Bool,
        recipe: Recipe?,
        autoSelectEngine: Bool,
        captureRunLog: Bool,
        context: ZeroPathLaunchContext
    ) async throws {
        let profile = context.profile
        var environment = environment
        let plan = context.plan

        let qos = RuntimeLaunchOptimizer.processQualityOfService(for: profile)
        let launchArgs = RuntimeLaunchOptimizer.startArguments(
            profile: profile,
            executable: url,
            extraArgs: args
        )

        let capture: ProgramRunCapture?
        if captureRunLog {
            let prepared = try ProgramRunLogStore.prepareRunCapture(programURL: url, bottle: bottle)
            capture = prepared
            Task { @MainActor in
                ProgramRunLogStore.shared.adoptPreparedCapture(prepared)
            }
            if environment["WINEDEBUG"] == nil {
                if ProgramRunLogStore.verboseWineDebugEnabled {
                    environment["WINEDEBUG"] = ProgramRunLogStore.verboseWineDebugChannels
                } else {
                    environment["WINEDEBUG"] = ProgramRunLogStore.performanceWineDebugChannels
                }
            }
        } else {
            capture = nil
        }

        let verboseCapture = capture != nil && ProgramRunLogStore.verboseWineDebugEnabled
        let fileCaptureOnly = verboseCapture
        let quiet = !fileCaptureOnly && (
            capture != nil || RuntimeLaunchOptimizer.shouldQuietProcessOutput(for: profile)
        )
        let stream = try await Self.spawnRunProgramStream(
            url: url,
            launchArgs: launchArgs,
            bottle: bottle,
            environment: environment,
            qualityOfService: qos,
            quiet: quiet,
            fileCaptureOnly: fileCaptureOnly,
            capture: capture,
            engine: context.launchEngine
        )

        let runID = capture?.record.id
        let logFileURL = capture?.fileURL
        let readyViaZeroPath = plan.readinessSkipped
        let dispatchSeconds = Date().timeIntervalSince(context.launchStart)
        let consume: () async -> Void = {
            var exitCode: Int32?
            var heartbeatTask: Task<Void, Never>?
            var sawProcessStart = false

            for await output in stream {
                switch output {
                case .started(let process):
                    sawProcessStart = true
                    BottleProcessRegistry.shared.register(process, bottle: bottle)
                    if let runID {
                        let pid = process.processIdentifier
                        await MainActor.run {
                            ProgramRunLogStore.shared.attachHostProcess(
                                runID: runID,
                                processID: pid
                            )
                        }
                        let trackedPID = pid
                        let trackedRunID = runID
                        let trackedLogURL = logFileURL
                        heartbeatTask = Task.detached {
                            var tick = 0
                            // One handle for the whole run: reopening the
                            // log file every 10 s forced the kernel to
                            // re-resolve the path and pay open/close
                            // syscall pairs for the lifetime of the game.
                            var handle: FileHandle?
                            defer { try? handle?.close() }
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(10))
                                guard !Task.isCancelled else { return }
                                if kill(trackedPID, 0) != 0 {
                                    return
                                }
                                tick += 1
                                let line = "[heartbeat] still running (tick \(tick), pid \(trackedPID))\n"
                                if let trackedLogURL {
                                    if handle == nil {
                                        handle = try? FileHandle(forWritingTo: trackedLogURL)
                                        _ = try? handle?.seekToEnd()
                                    }
                                    if let data = line.data(using: .utf8) {
                                        try? handle?.write(contentsOf: data)
                                    }
                                }
                                if tick == 1 || tick % 3 == 0 {
                                    await MainActor.run {
                                        ProgramRunLogStore.shared.noteHeartbeat(
                                            runID: trackedRunID,
                                            tick: tick,
                                            processID: trackedPID
                                        )
                                    }
                                }
                            }
                        }
                    }
                case .message, .error:
                    break
                case .terminated(let process):
                    exitCode = process.terminationStatus
                }
            }
            heartbeatTask?.cancel()
            await ProgramRunFinalizer.finalize(
                runID: runID,
                capture: capture,
                programURL: url,
                bottle: bottle,
                exitCode: exitCode
            )
            // ZeroPath bookkeeping: once a launch has provably reached
            // the running state, the prefix state it ran against is the
            // confirmed-good baseline. On the double (confirming) pass
            // this re-execs the program; on later passes the intent
            // re-check repairs any wineserver flush clobber.
            if sawProcessStart, processStillHealthy(exitCode: exitCode) {
                DoubleLaunchExecutor.armBaseline(bottle: bottle, engineBuildID: context.engineBuildID)
            }
            LaunchLatencyTelemetry.record(LaunchLatencyEvent(
                bottleKey: context.bottleKey,
                startedAt: context.launchStart,
                readinessSeconds: readyViaZeroPath ? 0 : dispatchSeconds,
                dispatchSeconds: dispatchSeconds
            ))
            LaunchLatencyTelemetry.logSummary()
            if !context.displayIntents.isEmpty {
                _ = LaunchPathPreflight.confirmIntent(bottle: bottle, intents: context.displayIntents)
            }
            if plan.doubleLaunch && sawProcessStart {
                Logger.wineKit.info("ZeroPath: confirming pass complete, relaunching")
                var relaunchEnvironment = environment
                DoubleLaunchExecutor.markExecApplied(
                    record: .init(doubleLaunch: true, readinessSkipped: false),
                    environment: &relaunchEnvironment
                )
                try? await Wine.runProgram(
                    at: url,
                    args: args,
                    bottle: bottle,
                    environment: relaunchEnvironment,
                    wait: wait,
                    applyDXVK: applyDXVK,
                    recipe: recipe,
                    autoSelectEngine: autoSelectEngine,
                    captureRunLog: captureRunLog
                )
            }
        }

        if wait {
            await consume()
            return
        }

        Task(priority: .userInitiated) {
            await consume()
        }
    }

    private static func processStillHealthy(exitCode: Int32?) -> Bool {
        guard let exitCode else { return true }
        return exitCode == 0
    }

    /// Spawn the wine process for a program launch, finalizing the run
    /// record when the binary cannot be spawned at all so the run does
    /// not stay "running" forever.
    private static func spawnRunProgramStream(
        url: URL,
        launchArgs: [String],
        bottle: Bottle,
        environment: [String: String],
        qualityOfService: QualityOfService = .userInitiated,
        quiet: Bool = false,
        fileCaptureOnly: Bool = false,
        capture: ProgramRunCapture?,
        engine: (any WineEngine)? = nil
    ) async throws -> AsyncStream<ProcessOutput> {
        do {
            return try Self.runWineProcess(
                name: url.lastPathComponent,
                args: launchArgs,
                bottle: bottle,
                environment: environment,
                executableURL: url,
                qualityOfService: qualityOfService,
                quiet: quiet,
                logFileHandle: capture?.fileHandle,
                systemLog: false,
                fileCaptureOnly: fileCaptureOnly,
                engine: engine
            )
        } catch {
            if let capture {
                try? capture.fileHandle.close()
                let runID = capture.record.id
                await MainActor.run {
                    ProgramRunLogStore.shared.finishRun(runID: runID, exitCode: -1)
                }
            }
            throw error
        }
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        let profile = RuntimeLaunchOptimizer.profile(forExecutableAt: url)
        let extra = args.split { $0.isWhitespace }.map(String.init)
        let startBits = RuntimeLaunchOptimizer.startArguments(
            profile: profile,
            executable: url,
            extraArgs: extra
        )
        let startCmd = startBits.map { $0.posixQuoted }.joined(separator: " ")
        var wineCmd = "\(wineBinary.path.posixQuoted) \(startCmd)"
        let env = constructWineEnvironment(
            for: bottle,
            environment: environment,
            executableURL: url
        )
        for environment in env {
            guard let key = sanitizedEnvKey(environment.key) else { continue }
            wineCmd = "\(key)=\(environment.value.posixQuoted) " + wineCmd
        }

        return wineCmd
    }

    /// Shell `KEY=value` prefixes need valid identifiers; user-entered
    /// variable names may contain anything.
    private static func sanitizedEnvKey(_ key: String) -> String? {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        var scalars = String.UnicodeScalarView()
        for scalar in key.unicodeScalars {
            scalars.append(allowed.contains(scalar) ? scalar : "_")
        }
        var sanitized = String(scalars)
        if let first = sanitized.first, first.isNumber {
            sanitized = "_" + sanitized
        }
        return sanitized.count > 1 ? sanitized : nil
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        let wineName = wineBinary.lastPathComponent
        var cmd = """
        export PATH=\"\(WhiskyWineInstaller.binFolder.path):$PATH\"
        export WINE=\"\(wineName)\"
        """

        let env = constructWineEnvironment(for: bottle)
        for environment in env {
            cmd += "\nexport \(environment.key)=\"\(environment.value)\""
        }

        let driveC = bottle.url.appending(path: "drive_c").path
        cmd += """

        cd "\(driveC)"
        clear
        echo "MacBottle bottle: \(bottle.settings.name)"
        echo "Wine: $($WINE --version 2>/dev/null)"
        echo "WINEPREFIX: $WINEPREFIX"
        echo "Commands: wine, winecfg, wineboot, regedit"
        """

        return cmd
    }

}

enum WineInterfaceError: Error {
    case invalidResponse
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    public static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.whiskyBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }
        purgeOldLogs()

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }

    /// Every wine invocation creates a timestamped log; without a sweep
    /// they accumulate forever. Match the run-log store's 7-day
    /// retention.
    private static func purgeOldLogs(maxAgeDays: Int = 7) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: Self.logsFolder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(Double(-maxAgeDays) * 24 * 60 * 60)
        for file in files where file.pathExtension == "log" {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: file)
        }
    }
}
