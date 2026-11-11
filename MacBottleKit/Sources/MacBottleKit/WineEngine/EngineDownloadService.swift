//
//  EngineDownloadService.swift
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
import os.log

public enum EngineDownloadError: Error, LocalizedError {
    case feedUnavailable(URL)

    public var errorDescription: String? {
        switch self {
        case .feedUnavailable(let url):
            return "The engine feed at \(url.host ?? url.absoluteString) is unavailable."
        }
    }
}

public struct EngineDownloadProgress: Sendable, Equatable {    public var fraction: Double
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var bytesPerSecond: Double
    public var currentFile: String

    public init(
        fraction: Double,
        completedBytes: Int64,
        totalBytes: Int64,
        bytesPerSecond: Double,
        currentFile: String
    ) {
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.currentFile = currentFile
    }
}

/// Downloads an engine archive with resume support, then decides whether
/// its digest matches the archive the user previously accepted.
///
/// This deliberately does not pass the remembered digest to
/// `ChunkedDownloader`: a mismatch there could mean either corruption or
/// a legitimate upstream update, and only the trust store can tell the
/// difference. The archive is downloaded to a candidate file, hashed,
/// compared, and moved into place only after the decision.
public final class EngineDownloadService: @unchecked Sendable {
    public static let shared = EngineDownloadService()

    private let trustStore: EngineArchiveTrustStore
    private let downloader: ChunkedDownloader
    private let validateArchive: Bool

    public init(
        trustStore: EngineArchiveTrustStore = .shared,
        downloader: ChunkedDownloader = ChunkedDownloader(),
        validateArchive: Bool = true
    ) {
        self.trustStore = trustStore
        self.downloader = downloader
        self.validateArchive = validateArchive
    }

    @discardableResult
    public func download(
        from url: URL,
        to destination: URL,
        expectedSHA256: String? = nil,
        acceptingChangedDigest: Bool = false,
        onProgress: (@Sendable (EngineDownloadProgress) -> Void)? = nil
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let candidate = destination
            .deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).candidate-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: candidate) }

        do {
            try await downloader.download(
                jobs: [
                    DownloadJob(
                        url: url,
                        destination: candidate,
                        expectedSize: 0,
                        expectedSha256: expectedSHA256
                    )
                ],
                onProgress: { progress in
                    onProgress?(
                        EngineDownloadProgress(
                            fraction: progress.fraction,
                            completedBytes: progress.completedUnits,
                            totalBytes: progress.totalUnits,
                            bytesPerSecond: progress.bytesPerSecond,
                            currentFile: progress.currentFile
                        )
                    )
                }
            )
        } catch let error as URLError where error.code == .badServerResponse {
            throw EngineDownloadError.feedUnavailable(url)
        }
        let digest = ChunkedDownloader.sha256Hex(of: candidate)
        guard !digest.isEmpty else {
            throw EngineArchiveTrustError.invalidArchive
        }

        if let expectedSHA256 {
            guard digest == expectedSHA256.lowercased() else {
                throw EngineArchiveTrustError.digestChanged(
                    expected: expectedSHA256,
                    actual: digest
                )
            }
            // A pinned catalog digest is authoritative; record it so a
            // later unpinned download still has a baseline.
            trustStore.record(url: url, sha256: digest, note: "pinned catalog")
        } else {
            switch trustStore.decision(url: url, sha256: digest) {
            case .trusted:
                break
            case .firstUse:
                trustStore.record(url: url, sha256: digest, note: "first use")
            case .changed(let expected, let actual):
                guard acceptingChangedDigest else {
                    throw EngineArchiveTrustError.digestChanged(expected: expected, actual: actual)
                }
                trustStore.record(url: url, sha256: digest, note: "user accepted changed archive")
            }
        }

        if validateArchive {
            let entries = try Tar.list(candidate)
            guard !entries.isEmpty else {
                throw EngineArchiveTrustError.invalidArchive
            }
        }

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: candidate, to: destination)
        Logger.wineKit.info("EngineDownloadService: verified engine archive at \(destination.path, privacy: .public)")
        return destination
    }
}
