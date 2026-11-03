//
//  RecipeStore.swift
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

/// Loads recipes that ship with the app bundle.
///
/// Recipes live in the MacBottleKit package as JSON resources under
/// `Recipes/<platform>/<id>.json`. At build time they are copied into the
/// bundle by SwiftPM's resource processing. At runtime we walk the bundle's
/// `Recipes` directory and decode every `.json` file we find.
///
/// The loader is intentionally strict: a malformed recipe is logged and
/// skipped, but never silently accepted with incomplete data. CI catches
/// malformed recipes in PR review; this runtime check is a second line of
/// defense for end users.
///
/// Results are cached in memory on first access because recipes ship with
/// the app and never change at runtime. The cache is per-`RecipeStore`
/// instance to keep tests hermetic.
public final class RecipeStore: @unchecked Sendable {
    /// The process-wide store, bound to `MacBottleKit`'s resource bundle.
    /// Tests should construct their own `RecipeStore(bundle:)` for hermetic
    /// fixtures instead of mutating this instance.
    public static let shared = RecipeStore(bundle: .module, remoteCache: .default)

    private let bundle: Bundle
    private let remoteCache: RecipeCache?
    private let lock = NSLock()
    private var cache: [String: Recipe]?

    /// Construct a store backed by a specific bundle and, optionally, a
    /// remote-recipe cache. When a cache is supplied, recipes fetched
    /// from the upstream repository are merged on top of the bundled set
    /// at read time; cache entries win on conflict because they are the
    /// more recent source of truth.
    ///
    /// `Bundle.module` is internal to the package, so callers outside
    /// `MacBottleKit` (the app target, tests) must pass `.module` from within
    /// their own module or use `RecipeStore.shared`.
    public init(bundle: Bundle, remoteCache: RecipeCache? = nil) {
        self.bundle = bundle
        self.remoteCache = remoteCache
    }

    /// Returns every recipe available to the app, keyed by `id`.
    ///
    /// Merges two sources:
    ///
    /// 1. Recipes bundled with the app build (`Bundle.module`'s
    ///    `Recipes/` resource directory). Always present, never changes
    ///    at runtime. Acts as an offline baseline.
    /// 2. Recipes previously accepted from the upstream repository and
    ///    stored under `RecipeCache.default`. When a recipe exists in
    ///    both sources, the cache wins because it is the user's freshly
    ///    accepted copy.
    ///
    /// Missing `Recipes/` directory is treated as "no recipes shipped" and
    /// returns the cache-only set (which may be empty on first launch).
    public func loadAll() -> [String: Recipe] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache { return cached }

        var merged = Self.scan(bundle: bundle)
        if let remote = remoteCache?.loadAll(), !remote.isEmpty {
            merged.merge(remote, uniquingKeysWith: { _, remoteWins in remoteWins })
        }
        cache = merged
        return merged
    }

    /// Drop the in-memory cache. Intended for tests only; the shipped app
    /// has no reason to invalidate because resources are read-only.
    public func invalidateCache() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    private static func scan(bundle: Bundle) -> [String: Recipe] {
        guard let rootURL = bundle.url(forResource: "Recipes", withExtension: nil) else {
            Logger.wineKit.info("MacBottle: no Recipes directory in bundle; shipping empty recipe set")
            return [:]
        }

        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var result: [String: Recipe] = [:]
        let decoder = JSONDecoder()

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "json" else { continue }
            // Skip the generated manifest; only recipe payloads belong
            // in the scan.
            guard url.lastPathComponent != "_index.json" else { continue }
            do {
                let data = try Data(contentsOf: url)
                let recipe = try decoder.decode(Recipe.self, from: data)
                let problems = RecipeValidator.errors(for: recipe)
                guard problems.isEmpty else {
                    Logger.wineKit.error(
                        "MacBottle: recipe \(recipe.id) failed semantic validation: \(problems.joined(separator: "; "))"
                    )
                    continue
                }
                if let existing = result[recipe.id] {
                    Logger.wineKit.error(
                        // swiftlint:disable:next line_length
                        "MacBottle: duplicate recipe id \(recipe.id), keeping \(existing.title), skipping \(recipe.title)"
                    )
                    continue
                }
                result[recipe.id] = recipe
            } catch {
                Logger.wineKit.error(
                    "MacBottle: failed to decode recipe at \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        Logger.wineKit.info("MacBottle: loaded \(result.count) recipe(s) from bundle")
        return result
    }

    /// Look up a single recipe by its stable id.
    public func recipe(id: String) -> Recipe? {
        loadAll()[id]
    }
}
