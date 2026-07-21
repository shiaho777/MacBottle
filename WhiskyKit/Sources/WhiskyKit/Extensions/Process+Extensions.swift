//
//  Process+Extensions.swift
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

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    func runStream(
        name: String,
        fileHandle: FileHandle?,
        quiet: Bool = false,
        systemLog: Bool = true,
        fileCaptureOnly: Bool = false
    ) throws -> AsyncStream<ProcessOutput> {
        let stream: AsyncStream<ProcessOutput>
        if fileCaptureOnly, let fileHandle {
            stream = makeFileCaptureStream(name: name, fileHandle: fileHandle)
            if systemLog {
                Logger.wineKit.info("Running process \(name) (file-capture)")
            }
            fileHandle.writeInfo(for: self)
        } else if quiet {
            stream = makeQuietStream(name: name, fileHandle: fileHandle)
            if systemLog {
                Logger.wineKit.info("Running process \(name) (quiet)")
            }
            fileHandle?.writeInfo(for: self)
        } else {
            stream = makeVerboseStream(name: name, fileHandle: fileHandle, systemLog: systemLog)
            if systemLog {
                self.logProcessInfo(name: name)
            }
            fileHandle?.writeInfo(for: self)
        }
        try run()
        return stream
    }

    private func makeVerboseStream(
        name: String,
        fileHandle: FileHandle?,
        systemLog: Bool
    ) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream(ProcessOutput.self, bufferingPolicy: .unbounded) { continuation in
            continuation.onTermination = { @Sendable termination in
                switch termination {
                case .finished:
                    break
                case .cancelled:
                    guard self.isRunning else { return }
                    self.terminate()
                @unknown default:
                    break
                }
            }

            continuation.yield(.started(self))

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.message(line))
                guard !line.isEmpty else { return }
                if systemLog {
                    Logger.wineKit.info("\(line, privacy: .public)")
                }
                fileHandle?.write(line: line)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.error(line))
                guard !line.isEmpty else { return }
                if systemLog {
                    Logger.wineKit.warning("\(line, privacy: .public)")
                }
                fileHandle?.write(line: line)
            }

            self.terminationHandler = { (process: Process) in
                do {
                    _ = try pipe.fileHandleForReading.readToEnd()
                    _ = try errorPipe.fileHandleForReading.readToEnd()
                    try fileHandle?.close()
                } catch {
                    Logger.wineKit.error("Error while clearing data: \(error)")
                }

                process.logTermination(name: name)
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    private func makeFileCaptureStream(name: String, fileHandle: FileHandle) -> AsyncStream<ProcessOutput> {
        let outPipe = Pipe()
        let errPipe = Pipe()
        standardOutput = outPipe
        standardError = errPipe

        return AsyncStream(ProcessOutput.self, bufferingPolicy: .unbounded) { continuation in
            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination, self.isRunning {
                    self.terminate()
                }
            }

            continuation.yield(.started(self))

            let box = FileWriteBox(handle: fileHandle, maxBytes: 12 * 1024 * 1024)
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                box.write(handle.availableData)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                box.write(handle.availableData)
            }

            self.terminationHandler = { (process: Process) in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let data = try? outPipe.fileHandleForReading.readToEnd() {
                    box.write(data)
                }
                if let data = try? errPipe.fileHandleForReading.readToEnd() {
                    box.write(data)
                }
                box.close()
                process.logTermination(name: name)
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    private func makeQuietStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        standardOutput = FileHandle.nullDevice
        standardError = FileHandle.nullDevice

        return AsyncStream(ProcessOutput.self, bufferingPolicy: .unbounded) { continuation in
            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination, self.isRunning {
                    self.terminate()
                }
            }

            continuation.yield(.started(self))

            self.terminationHandler = { (process: Process) in
                try? fileHandle?.close()
                process.logTermination(name: name)
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    private func logTermination(name: String) {
        if terminationStatus == 0 {
            Logger.wineKit.info(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        } else {
            Logger.wineKit.warning(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        }
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}

private final class FileWriteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?
    private let maxBytes: UInt64
    private var written: UInt64 = 0
    private var truncated = false

    init(handle: FileHandle, maxBytes: UInt64 = 12 * 1024 * 1024) {
        self.handle = handle
        self.maxBytes = maxBytes
    }

    func write(_ data: Data) {
        guard !data.isEmpty, !truncated else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        let remaining = maxBytes > written ? maxBytes - written : 0
        if remaining == 0 {
            markTruncatedLocked(handle: handle)
            return
        }
        if UInt64(data.count) <= remaining {
            handle.write(data)
            written += UInt64(data.count)
            return
        }
        let prefix = data.prefix(Int(remaining))
        if !prefix.isEmpty {
            handle.write(Data(prefix))
            written += UInt64(prefix.count)
        }
        markTruncatedLocked(handle: handle)
    }

    private func markTruncatedLocked(handle: FileHandle) {
        guard !truncated else { return }
        truncated = true
        let notice = "\n---- log truncated at \(maxBytes) bytes (capture size limit) ----\n"
        if let noticeData = notice.data(using: .utf8) {
            handle.write(noticeData)
            written += UInt64(noticeData.count)
        }
    }

    func close() {
        lock.lock()
        try? handle?.close()
        handle = nil
        lock.unlock()
    }
}

extension FileHandle {
    func nextLine() -> String? {
        guard let line = String(data: availableData, encoding: .utf8) else { return nil }
        if !line.isEmpty {
            return line
        } else {
            return nil
        }
    }
}
