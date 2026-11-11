//
//  WineInterface.swift
//  MacBottleKit
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

extension Wine {
    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:],
        engine: (any WineEngine)? = nil
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        var environment = environment

        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(
                for: bottle,
                environment: environment,
                engine: engine
            )
        }

        let stream: AsyncStream<ProcessOutput>
        do {
            stream = try runWineProcess(
                args: args,
                environment: environment,
                fileHandle: fileHandle,
                engine: engine
            )
        } catch {
            try? fileHandle.close()
            throw error
        }
        for await output in stream {
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
        BottleForceStop.forceStop(bottle: bottle, reason: "killBottle")
    }

    public static func enableDXVK(
        bottle: Bottle,
        engine: (any WineEngine)? = nil
    ) throws {
        let engine = engine ?? WineEngineRegistry.shared.current
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: engine.dxvkFolder.appending(path: "x64"),
            makeOriginalCopy: true
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: engine.dxvkFolder.appending(path: "x32"),
            makeOriginalCopy: true
        )
        try? Data(engine.identifier.utf8).write(to: dxvkMarkerURL(for: bottle), options: .atomic)
    }

    /// Restore the Wine DLLs snapshotted by `enableDXVK`. Safe to call
    /// when DXVK was never installed (no-op).
    public static func disableDXVK(bottle: Bottle) throws {
        let marker = dxvkMarkerURL(for: bottle)
        guard FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) else {
            return
        }
        let windows = bottle.url.appending(path: "drive_c").appending(path: "windows")
        try FileManager.default.restoreDLLs(in: windows.appending(path: "system32"))
        try FileManager.default.restoreDLLs(in: windows.appending(path: "syswow64"))
        try? FileManager.default.removeItem(at: marker)
    }

    private static func dxvkMarkerURL(for bottle: Bottle) -> URL {
        bottle.url.appending(path: ".macbottle-dxvk")
    }

    public static func enableDXMT(bottle: Bottle, engine: any WineEngine) throws {
        guard engine.supportsDXMT else { return }
        try disableDXVK(bottle: bottle)
        try disableVKD3D(bottle: bottle)
        let windows = bottle.url.appending(path: "drive_c").appending(path: "windows")
        try FileManager.default.replaceDLLs(
            in: windows.appending(path: "system32"),
            withContentsIn: engine.dxmtFolder.appending(path: "x64"),
            makeOriginalCopy: true
        )
        try FileManager.default.replaceDLLs(
            in: windows.appending(path: "syswow64"),
            withContentsIn: engine.dxmtFolder.appending(path: "x32"),
            makeOriginalCopy: true
        )
        try? Data().write(to: rendererMarkerURL("dxmt", bottle: bottle), options: .atomic)
    }

    public static func disableDXMT(bottle: Bottle) throws {
        let marker = rendererMarkerURL("dxmt", bottle: bottle)
        guard FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) else {
            return
        }
        let windows = bottle.url.appending(path: "drive_c").appending(path: "windows")
        try FileManager.default.restoreDLLs(in: windows.appending(path: "system32"))
        try FileManager.default.restoreDLLs(in: windows.appending(path: "syswow64"))
        try? FileManager.default.removeItem(at: marker)
    }

    public static func enableVKD3D(bottle: Bottle, engine: any WineEngine) throws {
        guard engine.supportsVKD3D else { return }
        try disableDXVK(bottle: bottle)
        try disableDXMT(bottle: bottle)
        let windows = bottle.url.appending(path: "drive_c").appending(path: "windows")
        try FileManager.default.replaceDLLs(
            in: windows.appending(path: "system32"),
            withContentsIn: engine.vkd3dFolder.appending(path: "x64"),
            makeOriginalCopy: true
        )
        try FileManager.default.replaceDLLs(
            in: windows.appending(path: "syswow64"),
            withContentsIn: engine.vkd3dFolder.appending(path: "x32"),
            makeOriginalCopy: true
        )
        try? Data().write(to: rendererMarkerURL("vkd3d", bottle: bottle), options: .atomic)
    }

    public static func disableVKD3D(bottle: Bottle) throws {
        let marker = rendererMarkerURL("vkd3d", bottle: bottle)
        guard FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) else {
            return
        }
        let windows = bottle.url.appending(path: "drive_c").appending(path: "windows")
        try FileManager.default.restoreDLLs(in: windows.appending(path: "system32"))
        try FileManager.default.restoreDLLs(in: windows.appending(path: "syswow64"))
        try? FileManager.default.removeItem(at: marker)
    }

    public static func disableAllRendererPayloads(bottle: Bottle) {
        try? disableDXVK(bottle: bottle)
        try? disableDXMT(bottle: bottle)
        try? disableVKD3D(bottle: bottle)
    }

    private static func rendererMarkerURL(_ name: String, bottle: Bottle) -> URL {
        bottle.url.appending(path: ".macbottle-\(name)")
    }
}

extension Wine {
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

    static func baseHostEnvironment(engine: (any WineEngine)? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let stripKeys = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "DYLD_FRAMEWORK_PATH",
            "DYLD_FALLBACK_LIBRARY_PATH",
            "DYLD_VERSIONED_LIBRARY_PATH",
            "DYLD_VERSIONED_FRAMEWORK_PATH",
            "LD_LIBRARY_PATH",
            "LD_PRELOAD"
        ]
        for key in stripKeys {
            env.removeValue(forKey: key)
        }
        for key in Array(env.keys) where key.hasPrefix("DYLD_") {
            env.removeValue(forKey: key)
        }

        let wineBin = engine?.wineBinary.deletingLastPathComponent().path
            ?? EngineInstaller.binFolder.path
        let pathParts = (env["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        if pathParts.contains(wineBin) {
            env["PATH"] = pathParts.joined(separator: ":")
        } else if pathParts.isEmpty {
            env["PATH"] = "\(wineBin):/usr/bin:/bin:/usr/sbin:/sbin"
        } else {
            env["PATH"] = ([wineBin] + pathParts).joined(separator: ":")
        }

        if env["HOME"]?.isEmpty != false {
            env["HOME"] = NSHomeDirectory()
        }
        if env["TMPDIR"]?.isEmpty != false {
            env["TMPDIR"] = FileManager.default.temporaryDirectory.path
        }
        if env["USER"]?.isEmpty != false {
            env["USER"] = NSUserName()
        }
        if env["LOGNAME"]?.isEmpty != false {
            env["LOGNAME"] = NSUserName()
        }
        if env["SHELL"]?.isEmpty != false {
            env["SHELL"] = "/bin/zsh"
        }
        return env
    }

    /// Construct an environment merging the bottle values with the given values
    static func constructWineEnvironment(
        for bottle: Bottle,
        environment: [String: String] = [:],
        executableURL: URL? = nil,
        engine: (any WineEngine)? = nil
    ) -> [String: String] {
        var result = baseHostEnvironment(engine: engine)
        result["WINEPREFIX"] = bottle.url.path
        result["WINEDEBUG"] = "-all"
        result["GST_DEBUG"] = "0"
        let dxvkAvailable = engine?.supportsDXVK ?? true
        bottle.settingsSnapshot.environmentVariables(wineEnv: &result, dxvkAvailable: dxvkAvailable)
        let profile = RuntimeLaunchOptimizer.profile(forExecutableAt: executableURL)
        result = RuntimeLaunchOptimizer.environment(
            profile: profile,
            bottleDXVKEnabled: bottle.settingsSnapshot.dxvk && dxvkAvailable,
            base: result
        )
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    static func constructWineServerEnvironment(
        for bottle: Bottle,
        environment: [String: String] = [:],
        engine: (any WineEngine)? = nil
    ) -> [String: String] {
        var result = baseHostEnvironment(engine: engine)
        result["WINEPREFIX"] = bottle.url.path
        result["WINEDEBUG"] = "-all"
        result["GST_DEBUG"] = "0"
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}

extension Wine {
    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        let profile = RuntimeLaunchOptimizer.profile(forExecutableAt: url)
        let extra = ShellArgumentParser.parse(args)
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
        export PATH=\"\(EngineInstaller.binFolder.path):$PATH\"
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
        echo "MacBottle bottle: \(bottle.settingsSnapshot.name)"
        echo "Wine: $($WINE --version 2>/dev/null)"
        echo "WINEPREFIX: $WINEPREFIX"
        echo "Commands: wine, winecfg, wineboot, regedit"
        """

        return cmd
    }

}
