//
//  ProcessRunner.swift
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

public struct ProcessRunResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public var standardOutputString: String {
        String(data: standardOutput, encoding: .utf8)
            ?? String(data: standardOutput, encoding: .isoLatin1)
            ?? ""
    }

    public var standardErrorString: String {
        String(data: standardError, encoding: .utf8)
            ?? String(data: standardError, encoding: .isoLatin1)
            ?? ""
    }

    public var isSuccess: Bool {
        exitCode == 0
    }
}

public enum ProcessRunner {
    public static func run(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessRunResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            if let environment {
                process.environment = environment
            }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            // Drain both pipes while the child runs. Reading only after
            // exit deadlocks as soon as a child writes more than the
            // kernel pipe buffer (~64 KB), which winetricks and steamcmd
            // routinely do.
            let outReader = PipeDrain(handle: stdout.fileHandleForReading)
            let errReader = PipeDrain(handle: stderr.fileHandleForReading)
            let gate = ResumeGate()

            process.terminationHandler = { finished in
                let outData = outReader.finish()
                let errData = errReader.finish()

                guard gate.claim() else { return }
                continuation.resume(
                    returning: ProcessRunResult(
                        exitCode: finished.terminationStatus,
                        standardOutput: outData,
                        standardError: errData
                    )
                )
            }

            do {
                try process.run()
            } catch {
                _ = outReader.finish()
                _ = errReader.finish()
                guard gate.claim() else { return }
                continuation.resume(throwing: error)
            }
        }
    }

    public static func run(
        path: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessRunResult {
        try await run(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment
        )
    }
}

/// Serializes reads for one pipe and keeps every byte the child wrote.
private final class PipeDrain: @unchecked Sendable {    private let handle: FileHandle
    private let lock = NSLock()
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            self?.readAvailable(from: handle)
        }
    }

    private func readAvailable(from handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
        } else {
            buffer.append(chunk)
        }
    }

    /// Stop the handler and drain whatever is still buffered. Called only
    /// after the child has exited, so `availableData` reaches EOF instead
    /// of blocking.
    func finish() -> Data {
        lock.lock()
        defer { lock.unlock() }
        handle.readabilityHandler = nil
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }
        return buffer
    }
}

/// Ensures a `CheckedContinuation` is resumed exactly once even when both
/// the spawn path and the termination handler race.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}
