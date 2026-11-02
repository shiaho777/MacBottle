//
//  EngineArchiveTrustStore.swift
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

public struct EngineArchiveTrustRecord: Codable, Sendable, Equatable {
    public var url: String
    public var sha256: String
    public var trustedAt: Date
    public var note: String?

    public init(url: String, sha256: String, trustedAt: Date = Date(), note: String? = nil) {
        self.url = url
        self.sha256 = sha256
        self.trustedAt = trustedAt
        self.note = note
    }
}

public enum EngineArchiveTrustDecision: Sendable, Equatable {
    case firstUse
    case trusted
    case changed(expected: String, actual: String)
}

/// Records the digest of the engine archive the user has actually
/// accepted. This is trust-on-first-use, not a substitute for a signed
/// manifest: it cannot protect the first download, but it turns every
/// later silent replacement of the archive into an explicit decision
/// instead of an invisible code swap.
public final class EngineArchiveTrustStore: @unchecked Sendable {
    public static let shared = EngineArchiveTrustStore()

    public let storeURL: URL
    private let lock = NSLock()

    public init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.storeURL = base
                .appending(path: Bundle.whiskyBundleIdentifier)
                .appending(path: "EngineTrust.json")
        }
    }

    public func decision(url: URL, sha256: String) -> EngineArchiveTrustDecision {
        lock.lock(); defer { lock.unlock() }
        guard let record = loadLocked()[url.absoluteString] else {
            return .firstUse
        }
        if record.sha256.lowercased() == sha256.lowercased() {
            return .trusted
        }
        return .changed(expected: record.sha256, actual: sha256)
    }

    public func record(url: URL, sha256: String, note: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        var records = loadLocked()
        records[url.absoluteString] = EngineArchiveTrustRecord(
            url: url.absoluteString,
            sha256: sha256,
            note: note
        )
        saveLocked(records)
    }

    public func forget(url: URL) {
        lock.lock(); defer { lock.unlock() }
        var records = loadLocked()
        records.removeValue(forKey: url.absoluteString)
        saveLocked(records)
    }

    public func record(for url: URL) -> EngineArchiveTrustRecord? {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()[url.absoluteString]
    }

    private func loadLocked() -> [String: EngineArchiveTrustRecord] {
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: EngineArchiveTrustRecord].self, from: data)) ?? [:]
    }

    private func saveLocked(_ records: [String: EngineArchiveTrustRecord]) {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            Logger.wineKit.error(
                "EngineArchiveTrustStore: save failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

public enum EngineArchiveTrustError: Error, LocalizedError {
    case digestChanged(expected: String, actual: String)
    case invalidArchive

    public var errorDescription: String? {
        switch self {
        case .digestChanged(let expected, let actual):
            return "The engine archive changed (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .invalidArchive:
            return "The downloaded engine archive is not a valid tar.gz file."
        }
    }
}
