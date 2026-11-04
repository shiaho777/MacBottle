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
    static let dxvkFolder: URL = EngineInstaller.libraryFolder.appending(path: "DXVK")
    public static var wineBinary: URL {
        let wine64 = EngineInstaller.binFolder.appending(path: "wine64")
        if FileManager.default.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return EngineInstaller.binFolder.appending(path: "wine")
    }
    private static var wineserverBinary: URL {
        EngineInstaller.binFolder.appending(path: "wineserver")
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
        fileHandle: FileHandle?,
        engine: (any WineEngine)? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment,
            executableURL: engine?.wineserverBinary ?? wineserverBinary,
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
                    executableURL: executableURL,
                    engine: engine
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
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:],
        engine: (any WineEngine)? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        do {
            return try runWineserverProcess(
                name: name, args: args,
                environment: constructWineServerEnvironment(
                    for: bottle,
                    environment: environment,
                    engine: engine
                ),
                fileHandle: fileHandle,
                engine: engine
            )
        } catch {
            try? fileHandle.close()
            throw error
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
        captureRunLog: Bool = true,
        onRunFinished: (@Sendable (Int32?) -> Void)? = nil
    ) async throws {
        // Resolve the engine before prewarming: the warmup must spawn the
        // same wineserver the launch will use, and engine auto-selection
        // flips the process-wide registry.
        let engineDecision: LaunchEnginePolicy.AppliedLaunch?
        if autoSelectEngine {
            engineDecision = LaunchEnginePolicy.applyForLaunch(
                executable: url,
                recipe: recipe,
                bottleDXVKEnabled: bottle.settingsSnapshot.dxvk,
                bottleEngineID: bottle.settingsSnapshot.engineID
            )
        } else {
            engineDecision = nil
        }
        let launchEngine = engineDecision?.engine ?? WineEngineRegistry.shared.current

        // Plan (PE scan, DXVK config, readiness fingerprint) and warmup
        // (wineserver spawn) touch disjoint state; racing them hides the
        // warmup latency behind the planning work instead of paying both
        // serially.
        async let warmup: Void = ensureBottleReady(bottle, engine: launchEngine)
        let launchContext = await planLaunch(
            url: url,
            bottle: bottle,
            recipe: recipe,
            applyDXVK: applyDXVK,
            engineDecision: engineDecision,
            launchEngine: launchEngine,
            environment: environment,
            args: args
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
            onRunFinished: onRunFinished,
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
        var jvmDetected: Bool
    }

    // swiftlint:disable:next function_parameter_count
    private static func planLaunch(
        url: URL,
        bottle: Bottle,
        recipe: Recipe?,
        applyDXVK: Bool,
        engineDecision: LaunchEnginePolicy.AppliedLaunch?,
        launchEngine: any WineEngine,
        environment: [String: String],
        args: [String]
    ) async -> ZeroPathLaunchContext {
        let profile = RuntimeLaunchOptimizer.profile(forExecutableAt: url)

        var shouldApplyDXVK = applyDXVK
            && launchEngine.supportsDXVK
            && RuntimeLaunchOptimizer.effectiveDXVKEnabled(
                profile: profile,
                bottleDXVKEnabled: bottle.settingsSnapshot.dxvk
            )
        let dxmtActive = recipe?.renderer == .dxmt && launchEngine.supportsDXMT
        let vkd3dActive = recipe?.renderer == .vkd3d && launchEngine.supportsVKD3D
        if dxmtActive || vkd3dActive {
            shouldApplyDXVK = false
        }
        if engineDecision?.decision.engineID == WineEngineCatalog.d3dMetalIdentifier {
            shouldApplyDXVK = false
        } else if recipe?.renderer == .d3dmetal {
            shouldApplyDXVK = false
        } else if recipe?.renderer == .moltenvk {
            shouldApplyDXVK = false
        } else if recipe?.renderer == .wined3d {
            shouldApplyDXVK = false
        }

        var dxvkConfigURL: URL?
        if dxmtActive {
            try? disableVKD3D(bottle: bottle)
            try? disableDXVK(bottle: bottle)
            try? enableDXMT(bottle: bottle, engine: launchEngine)
            await MainActor.run {
                ProgramLaunchCoordinator.shared.clearDXVK(bottle: bottle)
            }
        } else if vkd3dActive {
            try? disableDXMT(bottle: bottle)
            try? disableDXVK(bottle: bottle)
            try? enableVKD3D(bottle: bottle, engine: launchEngine)
            await MainActor.run {
                ProgramLaunchCoordinator.shared.clearDXVK(bottle: bottle)
            }
        } else if shouldApplyDXVK {
            try? disableDXMT(bottle: bottle)
            try? disableVKD3D(bottle: bottle)
            let engineID = buildID(for: launchEngine)
            let dxvkReady = await MainActor.run {
                ProgramLaunchCoordinator.shared.isDXVKReady(bottle: bottle, engineID: engineID)
            }
            if !dxvkReady {
                try? enableDXVK(bottle: bottle, engine: launchEngine)
                await MainActor.run {
                    ProgramLaunchCoordinator.shared.markDXVKReady(
                        bottle: bottle,
                        engineID: engineID
                    )
                }
            }
            // Per-game dxvk.conf: queue depth 1 + honest UMA budget.
            // Written under Application Support and handed to DXVK via
            // DXVK_CONFIG_FILE, so the game directory stays untouched.
            dxvkConfigURL = DXVKGameConf.apply(
                posture: .responsive(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory),
                executable: url
            )
        } else {
            // A recipe or engine may have overridden a bottle that had a
            // renderer payload installed. Restore the Wine DLLs instead of
            // leaving a half-switched prefix behind.
            disableAllRendererPayloads(bottle: bottle)
            await MainActor.run {
                ProgramLaunchCoordinator.shared.clearDXVK(bottle: bottle)
            }
        }

        var environment = environment
        if let dxvkConfigURL {
            environment["DXVK_CONFIG_FILE"] = dxvkConfigURL.path(percentEncoded: false)
        }
        let isVulkanRoute = recipe?.renderer == .moltenvk
            || (recipe == nil
                && engineDecision?.decision.importProfile?.graphicsAPIs.contains(.vulkan) == true)
        if dxmtActive {
            RendererEnvironment.applyDXMT(to: &environment)
        } else if vkd3dActive {
            RendererEnvironment.applyVKD3D(to: &environment)
        } else if isVulkanRoute {
            RendererEnvironment.applyMoltenVK(to: &environment, engine: launchEngine)
        } else if recipe?.renderer == .wined3d {
            RendererEnvironment.applyWineD3D(to: &environment)
        }
        if environment["WINEDLLOVERRIDES"]?.isEmpty == true {
            environment.removeValue(forKey: "WINEDLLOVERRIDES")
        }

        // ---- ZeroPath: predict prefix readiness, skip boot-check ----
        let launchStart = Date()
        let engineBuildID = buildID(for: launchEngine)
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

        // ---- JVM game posture: Java进程资源占用 ----
        var jvmDetected = false
        if JavaGameTuner.detect(
            executable: url,
            importProfile: engineDecision?.decision.importProfile,
            args: args
        ) != .none {
            jvmDetected = true
            let heap = JavaGameTuner.recommendedHeapMegabytes(
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
            )
            for (key, value) in JavaGameTuner.environmentPosture(
                existingJavaOptions: environment["_JAVA_OPTIONS"],
                heapMegabytes: heap
            ) {
                environment[key] = value
            }
            Logger.wineKit.info(
                "JavaTuner: JVM launch detected, heap target \(heap)M"
            )
        }
        // ---- end JVM posture ----

        let context = ZeroPathLaunchContext(
            engineDecision: engineDecision,
            launchEngine: launchEngine,
            profile: profile,
            plan: plan,
            bottleKey: bottleKey,
            engineBuildID: engineBuildID,
            launchStart: launchStart,
            displayIntents: displayIntents,
            resolvedEnvironment: environment,
            jvmDetected: jvmDetected
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
        onRunFinished: (@Sendable (Int32?) -> Void)?,
        context: ZeroPathLaunchContext
    ) async throws {
        let profile = context.profile
        var environment = environment
        let plan = context.plan

        let qos = context.jvmDetected
            ? JavaGameTuner.hostQualityOfService()
            : RuntimeLaunchOptimizer.processQualityOfService(for: profile)
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
                    captureRunLog: captureRunLog,
                    onRunFinished: nil
                )
            }
            onRunFinished?(exitCode)
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
    )[0].appending(path: "Logs").appending(path: Bundle.macBottleBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }
        purgeOldLogsIfNeeded()

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }

    /// The sweep used to run on every single wine invocation, which is an
    /// O(files) directory walk on the launch hot path. Once an hour is
    /// plenty for a 7-day retention policy.
    private static func purgeOldLogsIfNeeded() {
        let marker = Self.logsFolder.appending(path: ".last-purge")
        let fileManager = FileManager.default
        if let attrs = try? fileManager.attributesOfItem(atPath: marker.path(percentEncoded: false)),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 3600 {
            return
        }
        purgeOldLogs()
        try? Data().write(to: marker, options: .atomic)
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
