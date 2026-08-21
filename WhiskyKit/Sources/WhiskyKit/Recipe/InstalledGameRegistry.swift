//
//  InstalledGameRegistry.swift
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

/// Persistent record of a game the user has installed via MacBottle.
///
/// Bridges two otherwise-disconnected worlds: a `Recipe` (metadata about
/// how to run a game) and a `Bottle` (a specific wine prefix on disk).
/// Pairing them is what turns "18 cards in the library" into "18 games
/// I can click Play on".
public struct InstalledGame: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let recipeID: String
    /// Bottle directory backing this installation.
    public let bottleURL: URL
    /// Fully-resolved Windows-side path of the main .exe, e.g.
    /// `C:\\Program Files\\Steam\\steam.exe`. Optional because the user
    /// may have completed the installer flow but not yet pointed us at
    /// the main executable.
    public let mainExe: String?
    public let installedAt: Date

    public var id: String { recipeID }

    public init(recipeID: String, bottleURL: URL, mainExe: String?, installedAt: Date = Date()) {
        self.recipeID = recipeID
        self.bottleURL = bottleURL
        self.mainExe = mainExe
        self.installedAt = installedAt
    }
}

/// Process-wide registry keeping `InstalledGame` records in
/// `Application Support/<bundleID>/installed-games.json`.
///
/// Designed as a simple NSLock-guarded file store: the data volume is
/// always tiny (one record per installed game), lookups are rare (only
/// when the Library view refreshes), and consistency matters more than
/// throughput. No ceremony needed.
public final class InstalledGameRegistry: @unchecked Sendable {
    public static let shared = InstalledGameRegistry()

    private let storeURL: URL
    private let lock = NSLock()

    public init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: Bundle.whiskyBundleIdentifier)
            self.storeURL = base.appending(path: "installed-games.json")
        }
    }

    // MARK: - Read

    public func all() -> [InstalledGame] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    public func game(forRecipe id: String) -> InstalledGame? {
        all().first(where: { $0.recipeID == id })
    }

    // MARK: - Write

    public func record(_ game: InstalledGame) throws {
        lock.lock(); defer { lock.unlock() }
        var games = loadLocked()
        games.removeAll(where: { $0.recipeID == game.recipeID })
        games.append(game)
        try saveLocked(games)
    }

    public func remove(recipeID: String) throws {
        lock.lock(); defer { lock.unlock() }
        var games = loadLocked()
        let before = games.count
        games.removeAll(where: { $0.recipeID == recipeID })
        guard games.count != before else { return }
        try saveLocked(games)
    }

    // MARK: - Locked helpers

    private func loadLocked() -> [InstalledGame] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([InstalledGame].self, from: data)
        } catch {
            Logger.wineKit.error(
                "InstalledGameRegistry: decode failed, quarantining store: \(error.localizedDescription)"
            )
            quarantineCorruptStoreLocked()
            return []
        }
    }

    private func quarantineCorruptStoreLocked() {
        let backup = storeURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: storeURL, to: backup)
    }

    private func saveLocked(_ games: [InstalledGame]) throws {
        let parent = storeURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(games)
        try data.write(to: storeURL, options: .atomic)
    }
}
