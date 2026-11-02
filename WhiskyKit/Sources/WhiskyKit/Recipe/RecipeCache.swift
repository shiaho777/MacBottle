//
//  RecipeCache.swift
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

/// On-disk store for remotely-fetched recipes plus the small amount of
/// bookkeeping the sync engine needs across app launches.
///
/// Layout under the cache root (by default
/// `~/Library/Application Support/<bundleID>/RemoteRecipes/`):
///
///     RemoteRecipes/
///       meta.json                 ← ETag, last-known index, last sync time
///       recipes/
///         <id>.json               ← one file per cached recipe
///
/// `meta.json` intentionally lives alongside `recipes/` so a blunt "delete
/// RemoteRecipes folder" reset from support tickets clears every piece of
/// state in one step.
///
/// Concurrency model: every public method takes the store's lock; callers
/// do not need to serialise access themselves. The store is hot-paths
/// rare (sync is opt-in at app start and on user gesture) so a coarse
/// lock is fine.
public final class RecipeCache: @unchecked Sendable {
    public struct Meta: Codable, Sendable, Equatable {
        public var etag: String?
        public var index: RecipeIndex?
        public var lastSyncAt: Date?

        public init(etag: String? = nil, index: RecipeIndex? = nil, lastSyncAt: Date? = nil) {
            self.etag = etag
            self.index = index
            self.lastSyncAt = lastSyncAt
        }

        static let empty = Meta()
    }

    public let root: URL
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
    }

    /// Default root: `Application Support/<bundleID>/RemoteRecipes`. The
    /// directory is created lazily on first write.
    public static func defaultLocation() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appending(path: Bundle.whiskyBundleIdentifier)
            .appending(path: "RemoteRecipes")
    }

    public static let `default` = RecipeCache(root: defaultLocation())

    private var metaURL: URL {
        root.appending(path: "meta.json")
    }

    private var recipesRoot: URL {
        root.appending(path: "recipes")
    }

    private func recipeURL(for id: String) -> URL {
        // Recipe ids use `.` as a separator (`steam.2050650`). That's
        // filesystem-safe on APFS but we still URL-escape to be defensive.
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return recipesRoot.appending(path: "\(safe).json")
    }

    // MARK: - Meta

    public func loadMeta() -> Meta {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try Data(contentsOf: metaURL)
            return try JSONDecoder().decode(Meta.self, from: data)
        } catch {
            return .empty
        }
    }

    public func saveMeta(_ meta: Meta) throws {
        lock.lock(); defer { lock.unlock() }
        try ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(meta)
        try data.write(to: metaURL, options: .atomic)
    }

    // MARK: - Recipes

    /// Load every cached recipe, keyed by id. Malformed files are skipped
    /// with a log line, matching `RecipeStore`'s bundle-loading policy.
    public func loadAll() -> [String: Recipe] {
        lock.lock(); defer { lock.unlock() }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: recipesRoot, includingPropertiesForKeys: nil
        ) else {
            return [:]
        }

        var result: [String: Recipe] = [:]
        let decoder = JSONDecoder()
        for url in entries where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let recipe = try decoder.decode(Recipe.self, from: data)
                let problems = RecipeValidator.errors(for: recipe)
                guard problems.isEmpty else {
                    Logger.wineKit.error(
                        "MacBottle: cached recipe \(recipe.id) failed validation: \(problems.joined(separator: "; "))"
                    )
                    continue
                }
                result[recipe.id] = recipe
            } catch {
                Logger.wineKit.error(
                    // swiftlint:disable:next line_length
                    "MacBottle: cached recipe \(url.lastPathComponent) unreadable, skipping: \(error.localizedDescription)"
                )
            }
        }
        return result
    }

    public func loadRecipe(id: String) -> Recipe? {
        lock.lock(); defer { lock.unlock() }
        let url = recipeURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let recipe = try? JSONDecoder().decode(Recipe.self, from: data),
              RecipeValidator.errors(for: recipe).isEmpty else {
            return nil
        }
        return recipe
    }

    public func storeRecipe(_ recipe: Recipe) throws {
        lock.lock(); defer { lock.unlock() }
        try ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(recipe)
        try data.write(to: recipeURL(for: recipe.id), options: .atomic)
    }

    public func removeRecipe(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        let url = recipeURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Maintenance

    /// Delete every file under the cache root. Intended for support
    /// tickets and tests.
    public func reset() throws {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    private func ensureDirectories() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: recipesRoot.path) {
            try fileManager.createDirectory(at: recipesRoot, withIntermediateDirectories: true)
        }
    }
}
