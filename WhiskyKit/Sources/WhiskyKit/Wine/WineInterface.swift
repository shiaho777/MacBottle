//
//  WineInterface.swift
//  WhiskyKit
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

        let stream: AsyncStream<ProcessOutput>
        do {
            stream = try runWineProcess(args: args, environment: environment, fileHandle: fileHandle)
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

    static func baseHostEnvironment() -> [String: String] {
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

        let wineBin = WhiskyWineInstaller.binFolder.path
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
        executableURL: URL? = nil
    ) -> [String: String] {
        var result = baseHostEnvironment()
        result["WINEPREFIX"] = bottle.url.path
        result["WINEDEBUG"] = "-all"
        result["GST_DEBUG"] = "0"
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

    static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result = baseHostEnvironment()
        result["WINEPREFIX"] = bottle.url.path
        result["WINEDEBUG"] = "-all"
        result["GST_DEBUG"] = "0"
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}
