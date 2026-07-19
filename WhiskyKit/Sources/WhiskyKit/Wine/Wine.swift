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
import os.log

public class Wine {
    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
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
        systemLog: Bool = true
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
            systemLog: systemLog
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?,
        qualityOfService: QualityOfService = .userInitiated,
        quiet: Bool = false,
        systemLog: Bool = true
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary,
            fileHandle: fileHandle,
            qualityOfService: qualityOfService,
            quiet: quiet,
            systemLog: systemLog
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
        systemLog: Bool = true
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle: FileHandle?
        if let logFileHandle {
            fileHandle = logFileHandle
        } else if quiet {
            fileHandle = nil
        } else {
            fileHandle = try makeFileHandle()
            fileHandle?.writeApplicationInfo()
            if let fileHandle {
                fileHandle.writeInfo(for: bottle)
            }
        }

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
            systemLog: systemLog
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment),
            fileHandle: fileHandle
        )
    }

    public static func prewarmBottle(_ bottle: Bottle) async throws {
        let alreadyWarm = await MainActor.run {
            ProgramLaunchCoordinator.shared.isWarm(bottle: bottle)
        }
        if alreadyWarm { return }

        await MainActor.run {
            ProgramLaunchCoordinator.shared.beginWarmup(bottle: bottle)
        }
        do {
            let stream = try runWineserverProcess(
                name: "wineserver-prewarm",
                args: ["-p"],
                environment: constructWineServerEnvironment(for: bottle),
                fileHandle: nil
            )
            for await _ in stream { }
            await MainActor.run {
                ProgramLaunchCoordinator.shared.finishWarmup(bottle: bottle, success: true)
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
        await ensureBottleReady(bottle)

        let engineDecision: LaunchEnginePolicy.Decision?
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
        defer {
            if autoSelectEngine {
                LaunchEnginePolicy.restoreUserSelection()
            }
        }

        let profile = RuntimeLaunchOptimizer.profile(forExecutableAt: url)

        var shouldApplyDXVK = applyDXVK
            && RuntimeLaunchOptimizer.effectiveDXVKEnabled(
                profile: profile,
                bottleDXVKEnabled: bottle.settings.dxvk
            )
        if engineDecision?.engineID == WineEngineCatalog.d3dMetalIdentifier {
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
                try enableDXVK(bottle: bottle)
                await MainActor.run {
                    ProgramLaunchCoordinator.shared.markDXVKReady(bottle: bottle)
                }
            }
        }

        var environment = environment
        if environment["WINEDLLOVERRIDES"]?.isEmpty == true {
            environment.removeValue(forKey: "WINEDLLOVERRIDES")
        }

        DisplayPolicy.apply(for: profile, bottle: bottle)
        let qos = RuntimeLaunchOptimizer.processQualityOfService(for: profile)
        let launchArgs = RuntimeLaunchOptimizer.startArguments(
            profile: profile,
            executable: url,
            extraArgs: args
        )

        let capture: ProgramRunCapture?
        if captureRunLog {
            capture = try await MainActor.run {
                try ProgramRunLogStore.shared.beginRun(programURL: url, bottle: bottle)
            }
            if environment["WINEDEBUG"] == nil {
                if ProgramRunLogStore.verboseWineDebugEnabled {
                    environment["WINEDEBUG"] = ProgramRunLogStore.verboseWineDebugChannels
                } else {
                    environment["WINEDEBUG"] = "-all"
                }
            }
        } else {
            capture = nil
        }

        let quiet = capture == nil && RuntimeLaunchOptimizer.shouldQuietProcessOutput(for: profile)
        let stream = try Self.runWineProcess(
            name: url.lastPathComponent,
            args: launchArgs,
            bottle: bottle,
            environment: environment,
            executableURL: url,
            qualityOfService: qos,
            quiet: quiet,
            logFileHandle: capture?.fileHandle,
            systemLog: capture == nil
        )

        let runID = capture?.record.id
        let consume: () async -> Void = {
            var exitCode: Int32?
            var pending: [(String, Bool)] = []
            pending.reserveCapacity(64)

            let flush: () async -> Void = {
                guard let runID, !pending.isEmpty else {
                    pending.removeAll(keepingCapacity: true)
                    return
                }
                let batch = pending
                pending.removeAll(keepingCapacity: true)
                await MainActor.run {
                    for item in batch {
                        ProgramRunLogStore.shared.appendLine(runID: runID, line: item.0, isError: item.1)
                    }
                }
            }

            for await output in stream {
                switch output {
                case .started:
                    break
                case .message(let line):
                    if runID != nil {
                        pending.append((line, false))
                        if pending.count >= 32 {
                            await flush()
                        }
                    }
                case .error(let line):
                    if runID != nil {
                        pending.append((line, true))
                        if pending.count >= 32 {
                            await flush()
                        }
                    }
                case .terminated(let process):
                    exitCode = process.terminationStatus
                }
            }
            await flush()
            if let runID {
                await MainActor.run {
                    ProgramRunLogStore.shared.finishRun(runID: runID, exitCode: exitCode)
                }
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
        let startCmd = startBits.map { token in
            token.contains(" ") ? "\"\(token)\"" : token
        }.joined(separator: " ")
        var wineCmd = "\(wineBinary.esc) \(startCmd)"
        let env = constructWineEnvironment(
            for: bottle,
            environment: environment,
            executableURL: url
        )
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }

        return wineCmd
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

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        var environment = environment

        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }

        for await output in try runWineProcess(args: args, environment: environment, fileHandle: fileHandle) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        var output = try await runWine(["--version"], bottle: nil)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) async throws {
        try await runWineserver(["-k"], bottle: bottle)
    }

    public static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle,
        environment: [String: String] = [:],
        executableURL: URL? = nil
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "-all",
            "GST_DEBUG": "0"
        ]
        bottle.settings.environmentVariables(wineEnv: &result)
        let profile = RuntimeLaunchOptimizer.profile(forExecutableAt: executableURL)
        result = RuntimeLaunchOptimizer.environment(
            profile: profile,
            bottleDXVKEnabled: bottle.settings.dxvk,
            base: result
        )
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "-all",
            "GST_DEBUG": "0"
        ]
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
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

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }
}

extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    private static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    private static func queryRegistryKey(
        bottle: Bottle, key: String, name: String, type: RegistryType
    ) async throws -> String? {
        let output = try await runWine(["reg", "query", key, "-v", name], bottle: bottle)
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
    }

    public static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuild", data: "\(version)", type: .string)
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuildNumber", data: "\(version)", type: .string)
    }

    public static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await Wine.runWine(["winecfg", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponse
    }

    public static func buildVersion(bottle: Bottle) async throws -> String? {
        return try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    public static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output) else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
    }

    public static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    public static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await Wine.queryRegistryKey(bottle: bottle, key: RegistryKey.desktop.rawValue,
                                                     name: "LogPixels", type: .dword
        ) else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int = int else { return nil }
        return int
    }

    public static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    public static func control(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["control"], bottle: bottle)
    }

    @discardableResult
    public static func regedit(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["regedit"], bottle: bottle)
    }

    @discardableResult
    public static func cfg(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["winecfg"], bottle: bottle)
    }

    @discardableResult
    public static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        return try await Wine.runWine(["winecfg", "-v", win.rawValue], bottle: bottle)
    }
}
