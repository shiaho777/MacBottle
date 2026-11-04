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

import Darwin
import Foundation

public enum ProcessRunnerError: Error, LocalizedError, Equatable {
    case timedOut(seconds: Double)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "The process did not exit within \(seconds) seconds."
        }
    }
}

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
        environment: [String: String]? = nil,
        timeout: Duration? = nil
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
            let timeoutTask = Locked<Task<Void, Never>?>(nil)

            process.terminationHandler = { finished in
                let outData = outReader.finish()
                let errData = errReader.finish()

                guard gate.claim() else { return }
                timeoutTask.withLock { $0?.cancel() }
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
                return
            }

            if let timeout {
                let seconds = timeout.seconds
                let task = Task.detached {
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled, gate.claim() else { return }
                    terminate(process)
                    _ = outReader.finish()
                    _ = errReader.finish()
                    continuation.resume(throwing: ProcessRunnerError.timedOut(seconds: seconds))
                }
                timeoutTask.withLock { $0 = task }
            }
        }
    }

    /// Blocking variant for callers that cannot suspend (synchronous
    /// helpers such as `Tar` and the force-stop path).
    public static func runSync(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration? = nil
    ) throws -> ProcessRunResult {
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

        try process.run()

        // Drain both pipes on background queues while waiting: a child
        // that fills the kernel pipe buffer would otherwise block
        // forever.
        let outBox = DataBox()
        let errBox = DataBox()
        let drainGroup = DispatchGroup()
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.value = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.value = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            drainGroup.leave()
        }

        if let timeout {
            let deadline = Date().addingTimeInterval(timeout.seconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                terminate(process)
                process.waitUntilExit()
                drainGroup.wait()
                throw ProcessRunnerError.timedOut(seconds: timeout.seconds)
            }
        }

        process.waitUntilExit()
        drainGroup.wait()

        return ProcessRunResult(
            exitCode: process.terminationStatus,
            standardOutput: outBox.value,
            standardError: errBox.value
        )
    }

    /// Starts a child without waiting for it and hands the `Process`
    /// back, so callers that must track or kill it (wineserver prewarm)
    /// keep that ability.
    public static func launch(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        qualityOfService: QualityOfService = .default
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = environment
        }
        process.qualityOfService = qualityOfService
        try process.run()
        return process
    }

    public static func runSync(
        path: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration? = nil
    ) throws -> ProcessRunResult {
        try runSync(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment,
            timeout: timeout
        )
    }

    public static func launch(
        path: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        qualityOfService: QualityOfService = .default
    ) throws -> Process {
        try launch(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment,
            qualityOfService: qualityOfService
        )
    }

    /// SIGTERM, a short grace period, then SIGKILL. Shared by the async
    /// timeout path and `runSync` so escalation happens in one place.
    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    public static func run(
        path: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration? = nil
    ) async throws -> ProcessRunResult {
        try await run(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment,
            timeout: timeout
        )
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}

/// Minimal mutex-protected box for state shared with a timeout task.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
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
