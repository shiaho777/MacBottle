//
//  ChunkedDownloader.swift
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

public struct DownloadJob: Sendable {
    public let url: URL
    public let destination: URL
    public let expectedSize: Int64

    public init(url: URL, destination: URL, expectedSize: Int64) {
        self.url = url
        self.destination = destination
        self.expectedSize = expectedSize
    }
}

public struct DownloadProgress: Sendable, Equatable {
    public var completedUnits: Int64
    public var totalUnits: Int64
    public var completedFiles: Int
    public var totalFiles: Int
    public var bytesPerSecond: Double
    public var currentFile: String

    public var fraction: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1, Double(completedUnits) / Double(totalUnits))
    }
}

public actor ChunkedDownloader {
    public typealias ProgressHandler = @Sendable (DownloadProgress) -> Void

    private let session: URLSession
    private let maxConcurrent: Int
    private let chunkThreshold: Int64
    private let preferredChunkSize: Int64
    private let maxChunksPerFile: Int

    public init(
        maxConcurrent: Int = 10,
        chunkThreshold: Int64 = 8 * 1024 * 1024,
        preferredChunkSize: Int64 = 4 * 1024 * 1024,
        maxChunksPerFile: Int = 8,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        let config = sessionConfiguration ?? {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpMaximumConnectionsPerHost = max(16, maxConcurrent * 2)
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 60
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldUsePipelining = true
            return configuration
        }()
        self.session = URLSession(configuration: config)
        self.maxConcurrent = max(1, maxConcurrent)
        self.chunkThreshold = max(1, chunkThreshold)
        self.preferredChunkSize = max(256 * 1024, preferredChunkSize)
        self.maxChunksPerFile = max(1, maxChunksPerFile)
    }

    public func download(
        jobs: [DownloadJob],
        onProgress: ProgressHandler? = nil
    ) async throws {
        let totalBytes = jobs.reduce(Int64(0)) { $0 + max(Int64(0), $1.expectedSize) }
        let state = ProgressState(totalBytes: totalBytes, totalFiles: jobs.count)

        try await withThrowingTaskGroup(of: (Int64, String).self) { group in
            var nextIndex = 0

            func schedule(_ job: DownloadJob) {
                group.addTask {
                    let bytes = try await self.downloadOne(
                        job.url,
                        to: job.destination,
                        expectedSize: job.expectedSize
                    )
                    return (bytes, job.destination.lastPathComponent)
                }
            }

            while nextIndex < jobs.count && nextIndex < maxConcurrent {
                schedule(jobs[nextIndex])
                nextIndex += 1
            }

            while let (bytes, name) = try await group.next() {
                await state.addBytes(bytes)
                await state.finishFile()
                if let onProgress {
                    onProgress(await state.snapshot(currentFile: name))
                }
                if nextIndex < jobs.count {
                    schedule(jobs[nextIndex])
                    nextIndex += 1
                }
            }
        }
    }

    private func downloadOne(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64
    ) async throws -> Int64 {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let size = fileSize(at: destination),
           expectedSize > 0,
           size == expectedSize {
            return expectedSize
        }

        let partial = destination.appendingPathExtension("partial")
        let remote = try await probe(url: url)
        let totalSize = remote.contentLength > 0 ? remote.contentLength : expectedSize

        if remote.acceptsRanges,
           totalSize >= chunkThreshold {
            let size = try await downloadParallel(
                url: url,
                destination: destination,
                partial: partial,
                totalSize: totalSize
            )
            return size
        }

        if remote.acceptsRanges,
           let existing = fileSize(at: partial),
           existing > 0,
           totalSize <= 0 || existing < totalSize {
            try await downloadResuming(
                url: url,
                partial: partial,
                startOffset: existing,
                totalSize: totalSize
            )
        } else {
            try await downloadFresh(url: url, partial: partial)
        }

        let finalSize = fileSize(at: partial) ?? 0
        if finalSize == 0 {
            throw URLError(.zeroByteResource)
        }
        if expectedSize > 0, finalSize != expectedSize, totalSize > 0, finalSize != totalSize {
            throw URLError(.cannotParseResponse)
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
        return finalSize
    }

    private struct RemoteInfo {
        let acceptsRanges: Bool
        let contentLength: Int64
    }

    private func probe(url: URL) async throws -> RemoteInfo {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return RemoteInfo(acceptsRanges: false, contentLength: 0)
            }
            let accept = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased()
            let length = http.expectedContentLength > 0 ? http.expectedContentLength : 0
            return RemoteInfo(
                acceptsRanges: accept.contains("bytes"),
                contentLength: length
            )
        } catch {
            return RemoteInfo(acceptsRanges: false, contentLength: 0)
        }
    }

    private func downloadFresh(url: URL, partial: URL) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: partial.path) {
            try fileManager.removeItem(at: partial)
        }
        let (tempURL, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        try fileManager.moveItem(at: tempURL, to: partial)
    }

    private func downloadResuming(
        url: URL,
        partial: URL,
        startOffset: Int64,
        totalSize: Int64
    ) async throws {
        var request = URLRequest(url: url)
        if totalSize > 0 {
            request.setValue("bytes=\(startOffset)-\(totalSize - 1)", forHTTPHeaderField: "Range")
        } else {
            request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
        }

        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 206 || (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode != 206 {
            try await downloadFresh(url: url, partial: partial)
            return
        }

        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try Self.appendFile(at: tempURL, to: handle)
        try? FileManager.default.removeItem(at: tempURL)
    }

    private static let copyBufferSize = 4 * 1024 * 1024

    /// Streams `source` onto `output` through a bounded buffer instead of
    /// loading the whole segment into memory.
    private static func appendFile(at source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: copyBufferSize) {
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
    }

    private func downloadParallel(
        url: URL,
        destination: URL,
        partial: URL,
        totalSize: Int64
    ) async throws -> Int64 {
        let fileManager = FileManager.default
        let workDir = partial.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).parts")
        // The work directory survives failed attempts so completed parts
        // are reused on retry; it is removed only after successful
        // assembly.
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        let chunkCount = min(
            maxChunksPerFile,
            max(1, Int((totalSize + preferredChunkSize - 1) / preferredChunkSize))
        )
        let chunkLength = (totalSize + Int64(chunkCount) - 1) / Int64(chunkCount)

        let failures = FirstErrorBox()

        await withTaskGroup(of: Void.self) { group in
            var inflight = 0
            var next = 0

            func addIfNeeded(_ index: Int) -> Bool {
                let start = Int64(index) * chunkLength
                guard start < totalSize else { return false }
                let end = min(totalSize, start + chunkLength) - 1
                let expected = end - start + 1
                let partURL = workDir.appending(path: String(format: "part-%04d", index))
                if fileSize(at: partURL) == expected {
                    return false
                }
                group.addTask {
                    do {
                        try await self.downloadRange(
                            url: url,
                            start: start,
                            end: end,
                            expectedBytes: expected,
                            to: partURL
                        )
                    } catch {
                        failures.setIfFirst(error)
                    }
                }
                return true
            }

            while next < chunkCount && inflight < min(maxConcurrent, chunkCount) {
                if addIfNeeded(next) { inflight += 1 }
                next += 1
            }

            // A failing range must not cancel its in-flight siblings:
            // they are allowed to finish so the next attempt reuses
            // them. No new ranges are scheduled after a failure.
            while !group.isEmpty {
                await group.next()
                inflight -= 1
                guard failures.first == nil else { continue }
                while next < chunkCount && inflight < min(maxConcurrent, chunkCount) {
                    if addIfNeeded(next) { inflight += 1 }
                    next += 1
                }
            }
        }
        if let error = failures.first {
            throw error
        }

        if fileManager.fileExists(atPath: partial.path) {
            try fileManager.removeItem(at: partial)
        }
        fileManager.createFile(atPath: partial.path, contents: nil)
        let output = try FileHandle(forWritingTo: partial)
        defer { try? output.close() }

        for index in 0..<chunkCount {
            let partURL = workDir.appending(path: String(format: "part-%04d", index))
            try Self.appendFile(at: partURL, to: output)
        }

        let finalSize = fileSize(at: partial) ?? 0
        if finalSize == 0 {
            throw URLError(.zeroByteResource)
        }
        if finalSize != totalSize {
            throw URLError(.cannotParseResponse)
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
        try? fileManager.removeItem(at: workDir)
        return finalSize
    }

    private func downloadRange(
        url: URL,
        start: Int64,
        end: Int64,
        expectedBytes: Int64,
        to destination: URL
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206 || (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        let size = fileSize(at: destination) ?? 0
        if size != expectedBytes && http.statusCode == 206 {
            throw URLError(.cannotParseResponse)
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }
}

private final class FirstErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: Error?

    func setIfFirst(_ newError: Error) {
        lock.lock()
        defer { lock.unlock() }
        if error == nil {
            error = newError
        }
    }

    var first: Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}

private actor ProgressState {
    private let totalBytes: Int64
    private let totalFiles: Int
    private var completedBytes: Int64 = 0
    private var completedFiles: Int = 0
    private var windowStart = Date()
    private var windowBytes: Int64 = 0
    private var speed: Double = 0

    init(totalBytes: Int64, totalFiles: Int) {
        self.totalBytes = totalBytes
        self.totalFiles = totalFiles
    }

    func addBytes(_ delta: Int64) {
        completedBytes += delta
        windowBytes += delta
        let elapsed = Date().timeIntervalSince(windowStart)
        if elapsed >= 0.25 {
            speed = Double(windowBytes) / max(elapsed, 0.001)
            windowBytes = 0
            windowStart = Date()
        }
    }

    func finishFile() {
        completedFiles += 1
    }

    func snapshot(currentFile: String) -> DownloadProgress {
        DownloadProgress(
            completedUnits: completedBytes,
            totalUnits: max(totalBytes, completedBytes),
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            bytesPerSecond: speed,
            currentFile: currentFile
        )
    }
}
