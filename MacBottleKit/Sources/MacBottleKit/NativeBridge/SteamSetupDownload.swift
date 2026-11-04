//
//  SteamSetupDownload.swift
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

public enum SteamSetupError: Error, LocalizedError, Equatable {
    case invalidResponse(Int)
    case tooSmall(bytes: Int, minimum: Int)
    case notAnExecutable

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code):
            return "SteamSetup download failed with HTTP \(code)."
        case .tooSmall(let bytes, let minimum):
            return "The downloaded SteamSetup is \(bytes) bytes; expected at least \(minimum)."
        case .notAnExecutable:
            return "The downloaded SteamSetup is not a Windows executable."
        }
    }
}

public enum SteamSetupPayload {
    /// A real `SteamSetup.exe` is several megabytes; anything much
    /// smaller is an HTML error page or a truncated download.
    public static let minimumBytes = 512 * 1024

    public static func validate(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        )
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size >= minimumBytes else {
            throw SteamSetupError.tooSmall(bytes: size, minimum: minimumBytes)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let magic = try? handle.read(upToCount: 2)
        guard magic == Data([0x4D, 0x5A]) else {
            throw SteamSetupError.notAnExecutable
        }
    }
}

/// Streams `SteamSetup.exe` to a temporary file, reporting progress, and
/// refuses anything that is not a plausible Windows executable.
public final class SteamSetupDownloadService: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let defaultURL: URL = {
        guard let url = URL(
            string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
        ) else {
            preconditionFailure("SteamSetupDownloadService.defaultURL: hardcoded URL failed to parse")
        }
        return url
    }()

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var destinationURL: URL?
    private var onProgress: (@Sendable (Int64, Int64) -> Void)?

    public override init() {
        super.init()
    }

    public func download(
        from url: URL,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            self.onProgress = onProgress
            lock.unlock()

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            lock.lock()
            self.session = session
            lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let progress = onProgress
        lock.unlock()
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            finish(.failure(SteamSetupError.invalidResponse(http.statusCode)))
            return
        }

        do {
            try SteamSetupPayload.validate(at: location)
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "SteamSetup-\(UUID().uuidString).exe")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: location, to: destination)
            lock.lock()
            destinationURL = destination
            lock.unlock()
        } catch {
            finish(.failure(error))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        lock.lock()
        self.session = nil
        let destination = destinationURL
        destinationURL = nil
        lock.unlock()

        if let error {
            finish(.failure(error))
        } else if let destination {
            finish(.success(destination))
        } else {
            finish(.failure(URLError(.cannotCreateFile)))
        }
    }
}
