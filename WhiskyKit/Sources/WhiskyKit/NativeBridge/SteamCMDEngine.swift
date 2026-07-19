//
//  SteamCMDEngine.swift
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
import os.log

public struct SteamCMDProgress: Sendable, Equatable {
    public var fraction: Double
    public var detail: String
    public var bytesPerSecond: Double
    public var state: State

    public enum State: String, Sendable, Equatable {
        case bootstrapping
        case loggingIn
        case updating
        case validating
        case finished
        case needsGuard
        case failed
    }
}

public enum SteamCMDError: Error, LocalizedError {
    case bootstrapFailed(String)
    case binaryMissing
    case loginFailed(String)
    case updateFailed(String)
    case cancelled
    case needsSteamGuard
    case appIDInvalid

    public var errorDescription: String? {
        switch self {
        case .bootstrapFailed(let message):
            return "steamcmd bootstrap failed: \(message)"
        case .binaryMissing:
            return "steamcmd binary not found after install."
        case .loginFailed(let message):
            return "Steam login failed: \(message)"
        case .updateFailed(let message):
            return "app_update failed: \(message)"
        case .cancelled:
            return "steamcmd cancelled."
        case .needsSteamGuard:
            return "Steam Guard code required."
        case .appIDInvalid:
            return "Invalid Steam AppID."
        }
    }
}

public final class SteamCMDEngine: @unchecked Sendable {
    public static let shared = SteamCMDEngine()

    public static let downloadURL: URL = {
        guard let url = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz") else {
            preconditionFailure("SteamCMDEngine.downloadURL is invalid")
        }
        return url
    }()

    private let store: DepotStore
    private let lock = NSLock()
    private var currentProcess: Process?

    public init(store: DepotStore = DepotStore()) {
        self.store = store
    }

    public func ensureBootstrapped(
        onProgress: (@Sendable (SteamCMDProgress) -> Void)? = nil
    ) async throws -> URL {
        let root = store.steamCMDRoot
        let binary = root.appending(path: "steamcmd")
        if FileManager.default.fileExists(atPath: binary.path) {
            return binary
        }

        onProgress?(
            SteamCMDProgress(
                fraction: 0.02,
                detail: "Downloading steamcmd (macOS)…",
                bytesPerSecond: 0,
                state: .bootstrapping
            )
        )

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tarball = root.appending(path: "steamcmd_osx.tar.gz")
        let (temp, response) = try await URLSession.shared.download(from: Self.downloadURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SteamCMDError.bootstrapFailed("HTTP \(http.statusCode)")
        }
        if FileManager.default.fileExists(atPath: tarball.path) {
            try FileManager.default.removeItem(at: tarball)
        }
        try FileManager.default.moveItem(at: temp, to: tarball)

        onProgress?(
            SteamCMDProgress(
                fraction: 0.08,
                detail: "Extracting steamcmd…",
                bytesPerSecond: 0,
                state: .bootstrapping
            )
        )

        let extract = try await ProcessRunner.run(
            path: "/usr/bin/tar",
            arguments: ["-xzf", tarball.path, "-C", root.path]
        )
        if !extract.isSuccess {
            throw SteamCMDError.bootstrapFailed(
                "tar exit \(extract.exitCode): \(extract.standardErrorString)"
            )
        }

        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw SteamCMDError.binaryMissing
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        onProgress?(
            SteamCMDProgress(
                fraction: 0.09,
                detail: "Warming up steamcmd (first-run self-update)…",
                bytesPerSecond: 0,
                state: .bootstrapping
            )
        )
        _ = try? await ProcessRunner.run(
            executable: binary,
            arguments: ["+quit"],
            currentDirectory: root
        )

        return binary
    }

    public func updateApp(
        appID: Int,
        credentials: SteamCredentials,
        validate: Bool = true,
        onProgress: (@Sendable (SteamCMDProgress) -> Void)? = nil
    ) async throws {
        guard appID > 0 else { throw SteamCMDError.appIDInvalid }

        let binary = try await ensureBootstrapped(onProgress: onProgress)
        let installDir = store.libraryRoot(appID: appID)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        onProgress?(
            SteamCMDProgress(
                fraction: 0.1,
                detail: "Logging into Steam (native steamcmd)…",
                bytesPerSecond: 0,
                state: .loggingIn
            )
        )

        var args: [String] = [
            "+@sSteamCmdForcePlatformType", "windows",
            "+@sSteamCmdForcePlatformBitness", "64",
            "+@ShutdownOnFailedCommand", "1",
            "+@NoPromptForPassword", "1",
            "+force_install_dir", installDir.path
        ]

        if let code = credentials.steamGuardCode, !code.isEmpty, !credentials.isAnonymous {
            args += ["+set_steam_guard_code", code]
        }

        if credentials.isAnonymous {
            args += ["+login", "anonymous"]
        } else {
            args += ["+login", credentials.username, credentials.password]
        }

        args += ["+app_update", String(appID)]
        if validate {
            args.append("validate")
        }
        args.append("+quit")

        try await runSteamCMD(binary: binary, arguments: args, appID: appID, onProgress: onProgress)
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        currentProcess?.terminate()
        currentProcess = nil
    }

    private func runSteamCMD(
        binary: URL,
        arguments: [String],
        appID: Int,
        onProgress: (@Sendable (SteamCMDProgress) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.currentDirectoryURL = binary.deletingLastPathComponent()
            process.environment = [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "TERM": "dumb"
            ]

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            lock.lock()
            currentProcess = process
            lock.unlock()

            let parser = SteamCMDOutputParser(appID: appID)
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) {
                    let progress = parser.consume(text)
                    onProgress?(progress)
                }
            }

            process.terminationHandler = { proc in
                output.fileHandleForReading.readabilityHandler = nil
                self.lock.lock()
                self.currentProcess = nil
                self.lock.unlock()

                let finalProgress = parser.snapshot
                if proc.terminationStatus == 0 || parser.succeeded {
                    onProgress?(
                        SteamCMDProgress(
                            fraction: 1,
                            detail: "app_update \(appID) complete",
                            bytesPerSecond: finalProgress.bytesPerSecond,
                            state: .finished
                        )
                    )
                    continuation.resume()
                    return
                }

                if parser.needsGuard {
                    onProgress?(
                        SteamCMDProgress(
                            fraction: finalProgress.fraction,
                            detail: "Steam Guard code required",
                            bytesPerSecond: 0,
                            state: .needsGuard
                        )
                    )
                    continuation.resume(throwing: SteamCMDError.needsSteamGuard)
                    return
                }

                if parser.loginFailed {
                    continuation.resume(throwing: SteamCMDError.loginFailed(parser.lastErrorLine ?? "unknown"))
                    return
                }

                continuation.resume(
                    throwing: SteamCMDError.updateFailed(
                        parser.lastErrorLine ?? "exit \(proc.terminationStatus)"
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

final class SteamCMDOutputParser: @unchecked Sendable {
    private let appID: Int
    private let lock = NSLock()
    private var buffer = ""
    private(set) var fraction: Double = 0.12
    private(set) var detail: String = "steamcmd starting…"
    private(set) var bytesPerSecond: Double = 0
    private(set) var state: SteamCMDProgress.State = .loggingIn
    private(set) var succeeded = false
    private(set) var needsGuard = false
    private(set) var loginFailed = false
    private(set) var lastErrorLine: String?

    init(appID: Int) {
        self.appID = appID
    }

    var snapshot: SteamCMDProgress {
        lock.lock()
        defer { lock.unlock() }
        return SteamCMDProgress(
            fraction: fraction,
            detail: detail,
            bytesPerSecond: bytesPerSecond,
            state: state
        )
    }

    func consume(_ text: String) -> SteamCMDProgress {
        lock.lock()
        defer { lock.unlock() }
        buffer += text
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        if let last = lines.last, !text.hasSuffix("\n") {
            buffer = String(last)
        } else {
            buffer = ""
        }
        let completeLines = text.hasSuffix("\n") ? lines : lines.dropLast()
        for lineSub in completeLines {
            handle(line: String(lineSub))
        }
        return SteamCMDProgress(
            fraction: fraction,
            detail: detail,
            bytesPerSecond: bytesPerSecond,
            state: state
        )
    }

    private func handle(line raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        Logger.wineKit.info("steamcmd: \(line, privacy: .public)")

        let lower = line.lowercased()
        if lower.contains("steam guard")
            || lower.contains("two-factor")
            || lower.contains("mobile authenticator")
            || lower.contains("auth code") {
            needsGuard = true
            state = .needsGuard
            detail = line
            return
        }
        if lower.contains("login failure")
            || lower.contains("invalid password")
            || lower.contains("account logon denied") {
            loginFailed = true
            lastErrorLine = line
            state = .failed
            detail = line
            return
        }
        if lower.contains("error") || lower.contains("failure") {
            lastErrorLine = line
        }
        if lower.contains("success! app '\(appID)' fully installed")
            || lower.contains("fully installed,")
            || lower.contains("already up to date") {
            succeeded = true
            fraction = 1
            state = .finished
            detail = line
            return
        }
        if lower.contains("validating") {
            state = .validating
        } else if lower.contains("update state") || lower.contains("downloading") {
            state = .updating
        } else if lower.contains("logging in") || lower.contains("logged in") {
            state = .loggingIn
        }

        // Progress lines look like:
        // " Update state (0x61) downloading, progress: 12.34 (1234 / 5678)"
        if let range = lower.range(of: "progress:") {
            let after = String(lower[range.upperBound...])
            let numbers = after.compactMapNumbers()
            if let pct = numbers.first {
                fraction = min(0.99, max(0.12, pct / 100.0))
            }
            if numbers.count >= 3 {
                // not always bytes/sec
            }
            detail = line
            // speed: "at 1.2 MB/s" variants
            if let speed = parseSpeed(from: line) {
                bytesPerSecond = speed
            }
            return
        }

        if line.count < 200 {
            detail = line
        }
    }

    private func parseSpeed(from line: String) -> Double? {
        // e.g. "5.6 MB/s" or "900 KB/s"
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(KB|MB|GB)/s"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 3,
              let valueRange = Range(match.range(at: 1), in: line),
              let unitRange = Range(match.range(at: 2), in: line),
              let value = Double(line[valueRange]) else {
            return nil
        }
        switch line[unitRange].uppercased() {
        case "KB": return value * 1_000
        case "MB": return value * 1_000_000
        case "GB": return value * 1_000_000_000
        default: return nil
        }
    }
}

private extension String {
    func compactMapNumbers() -> [Double] {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: self) else { return nil }
            return Double(self[matchRange])
        }
    }
}
