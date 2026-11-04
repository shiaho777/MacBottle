//
//  BottleData.swift
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
import SemanticVersion

public struct BottleData: Codable {
    public static let containerDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Containers")
        .appending(path: Bundle.macBottleBundleIdentifier)

    public static let bottleEntriesDir = containerDir
        .appending(path: "BottleVM")
        .appendingPathExtension("plist")

    public static let defaultBottleDir = containerDir
        .appending(path: "Bottles")

    static let currentVersion = SemanticVersion(1, 0, 0)

    private var fileVersion: SemanticVersion
    private var storeURL: URL

    /// True when the on-disk store could not be decoded and was quarantined
    /// instead of being overwritten with an empty list.
    public private(set) var recoveredFromCorruptStore = false

    public var paths: [URL] = [] {
        didSet {
            guard !isDecoding else { return }
            encode()
        }
    }

    private var isDecoding = false

    public init() {
        self.init(storeURL: Self.bottleEntriesDir)
    }

    init(storeURL: URL) {
        self.storeURL = storeURL
        self.fileVersion = Self.currentVersion
        loadOrCreate()
    }

    @MainActor
    public mutating func loadBottles() -> [Bottle] {
        var bottles: [Bottle] = []

        for path in paths {
            let bottleMetadata = path
                .appending(path: "Metadata")
                .appendingPathExtension("plist")
                .path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: bottleMetadata) {
                bottles.append(Bottle(bottleUrl: path, isAvailable: true))
            } else {
                bottles.append(Bottle(bottleUrl: path))
            }
        }

        return bottles
    }

    // MARK: - Persistence

    private mutating func loadOrCreate() {
        let fileManager = FileManager.default
        let targetURL = storeURL
        guard fileManager.fileExists(atPath: storeURL.path(percentEncoded: false)) else {
            encode()
            return
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let decoded = try PropertyListDecoder().decode(BottleData.self, from: data)

            guard decoded.fileVersion == Self.currentVersion else {
                Logger.wineKit.error(
                    "BottleData: unsupported file version \(decoded.fileVersion, privacy: .public); quarantining store"
                )
                recover(reason: "unsupported-version")
                return
            }

            self = decoded
            self.storeURL = targetURL
            self.isDecoding = false
        } catch {
            let path = targetURL.path(percentEncoded: false)
            let message = error.localizedDescription
            Logger.wineKit.error(
                "BottleData: failed to decode store at \(path, privacy: .public): \(message, privacy: .public)"
            )
            recover(reason: "decode-failed")
        }
    }

    /// Reset to an empty list only after the unreadable original has been
    /// moved aside. If the move fails, keep the original file untouched and
    /// leave the in-memory list empty so the next launch can retry.
    private mutating func recover(reason: String) {
        let quarantined = quarantine(reason: reason)
        isDecoding = true
        fileVersion = Self.currentVersion
        paths = []
        isDecoding = false
        guard quarantined else { return }
        encode()
    }

    /// Move the unreadable store aside before a fresh one is written, so a
    /// corrupt plist never costs the user their bottle list.
    @discardableResult
    private mutating func quarantine(reason: String) -> Bool {
        let fileManager = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = storeURL
            .deletingLastPathComponent()
            .appending(path: "\(storeURL.lastPathComponent).\(reason)-\(stamp)")
        do {
            try fileManager.moveItem(at: storeURL, to: backup)
            recoveredFromCorruptStore = true
            Logger.wineKit.error(
                "BottleData: quarantined store at \(backup.path, privacy: .public)"
            )
            return true
        } catch {
            Logger.wineKit.error(
                "BottleData: could not quarantine store: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    private func encode() -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(self)
            try data.write(to: storeURL, options: .atomic)
            return true
        } catch {
            let path = storeURL.path(percentEncoded: false)
            let message = error.localizedDescription
            Logger.wineKit.error(
                "BottleData: failed to save store at \(path, privacy: .public): \(message, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case fileVersion
        case paths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decode(SemanticVersion.self, forKey: .fileVersion)
        self.paths = try container.decodeIfPresent([URL].self, forKey: .paths) ?? []
        self.storeURL = Self.bottleEntriesDir
        self.isDecoding = true
        self.recoveredFromCorruptStore = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileVersion, forKey: .fileVersion)
        try container.encode(paths, forKey: .paths)
    }
}
