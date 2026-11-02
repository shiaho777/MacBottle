//
//  RecipeProvisioner.swift
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

import CryptoKit
import Foundation
import os.log

/// The side-effectful half of a recipe: winetricks verbs and registry
/// writes. `RecipeApplier` deliberately stays pure and only merges
/// environment variables; this type runs the parts that mutate the
/// bottle, once per (bottle, recipe) pairing, with an on-disk receipt so
/// a failed or interrupted run resumes instead of repeating expensive
/// verbs.
public struct RecipeProvisioningPlan: Sendable, Equatable {
    public let verbs: [String]
    public let registry: [RegistryEntry]

    public init(recipe: Recipe) {
        self.verbs = recipe.winetricks
        self.registry = recipe.registry
    }

    public var isEmpty: Bool {
        verbs.isEmpty && registry.isEmpty
    }

    /// Stable identity of the recipe's side-effect payload. Environment
    /// changes do not re-run provisioning; a new verb or registry entry
    /// does.
    public var fingerprint: String {
        var material: [String] = ["verbs"]
        material.append(contentsOf: verbs.sorted())
        material.append("registry")
        material.append(contentsOf: registry.map(Self.canonical).sorted())
        let digest = SHA256.hash(data: Data(material.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonical(_ entry: RegistryEntry) -> String {
        "\(entry.path)|\(entry.key)|\(entry.type.rawValue)|\(entry.value)"
    }
}

public struct RecipeProvisioningRecord: Codable, Sendable, Equatable {
    public var recipeID: String
    public var fingerprint: String
    public var completedVerbs: [String]
    public var completedRegistry: [String]
    public var appliedAt: Date?

    public init(
        recipeID: String,
        fingerprint: String,
        completedVerbs: [String] = [],
        completedRegistry: [String] = [],
        appliedAt: Date? = nil
    ) {
        self.recipeID = recipeID
        self.fingerprint = fingerprint
        self.completedVerbs = completedVerbs
        self.completedRegistry = completedRegistry
        self.appliedAt = appliedAt
    }

    public var isComplete: Bool {
        appliedAt != nil
    }
}

public enum RecipeProvisioningError: Error, LocalizedError {
    case winetricksUnavailable(URL)
    case verbFailed(verb: String, output: String)
    case registryFailed(entry: RegistryEntry, output: String)

    public var errorDescription: String? {
        switch self {
        case .winetricksUnavailable(let url):
            return "winetricks is not available at \(url.path)."
        case .verbFailed(let verb, let output):
            return "winetricks \(verb) failed: \(Self.tail(output))"
        case .registryFailed(let entry, let output):
            return "registry write \(entry.path)\\\(entry.key) failed: \(Self.tail(output))"
        }
    }

    private static func tail(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 600 else { return trimmed }
        return String(trimmed.suffix(600))
    }
}

/// On-disk receipts under
/// `Application Support/<bundleID>/RecipeProvisioning/<bottleKey>.json`.
public final class RecipeProvisioningStore: @unchecked Sendable {
    public static let shared = RecipeProvisioningStore()

    public let root: URL
    private let lock = NSLock()

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.root = base
                .appending(path: Bundle.whiskyBundleIdentifier)
                .appending(path: "RecipeProvisioning")
        }
    }

    public func record(bottleKey: String) -> RecipeProvisioningRecord? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL(bottleKey: bottleKey)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecipeProvisioningRecord.self, from: data)
    }

    public func save(_ record: RecipeProvisioningRecord, bottleKey: String) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: fileURL(bottleKey: bottleKey), options: .atomic)
    }

    public func remove(bottleKey: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(bottleKey: bottleKey))
    }

    private func fileURL(bottleKey: String) -> URL {
        root.appending(path: "\(bottleKey).json")
    }
}

/// Runs winetricks verbs and registry writes, resumably.
public actor RecipeProvisioner {
    public static let shared = RecipeProvisioner()

    public typealias VerbRunner = @Sendable (String, Bottle) async throws -> Void
    public typealias RegistryRunner = @Sendable (RegistryEntry, Bottle) async throws -> Void

    private let store: RecipeProvisioningStore
    private let runVerb: VerbRunner
    private let runRegistry: RegistryRunner

    public init(
        store: RecipeProvisioningStore = .shared,
        runVerb: VerbRunner? = nil,
        runRegistry: RegistryRunner? = nil
    ) {
        self.store = store
        self.runVerb = runVerb ?? Self.defaultVerbRunner
        self.runRegistry = runRegistry ?? Self.defaultRegistryRunner
    }

    /// Returns true when this call performed work, false when the recipe
    /// was already fully applied.
    @discardableResult
    public func provisionIfNeeded(
        recipe: Recipe,
        bottle: Bottle,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> Bool {
        let plan = RecipeProvisioningPlan(recipe: recipe)
        guard !plan.isEmpty else { return false }

        let bottleKey = ProgramRunLogStore.bottleKey(for: bottle)
        var record: RecipeProvisioningRecord
        if let existing = store.record(bottleKey: bottleKey),
           existing.recipeID == recipe.id,
           existing.fingerprint == plan.fingerprint {
            record = existing
        } else {
            record = RecipeProvisioningRecord(
                recipeID: recipe.id,
                fingerprint: plan.fingerprint
            )
        }
        if record.isComplete { return false }

        var didWork = false
        for verb in plan.verbs where !record.completedVerbs.contains(verb) {
            progress?("winetricks \(verb)")
            try await runVerb(verb, bottle)
            record.completedVerbs.append(verb)
            try store.save(record, bottleKey: bottleKey)
            didWork = true
        }

        for entry in plan.registry {
            let key = Self.registryKey(entry)
            guard !record.completedRegistry.contains(key) else { continue }
            progress?("registry \(entry.path)\\\(entry.key)")
            try await runRegistry(entry, bottle)
            record.completedRegistry.append(key)
            try store.save(record, bottleKey: bottleKey)
            didWork = true
        }

        record.appliedAt = Date()
        try store.save(record, bottleKey: bottleKey)
        return didWork
    }

    public func invalidate(recipeID: String, bottle: Bottle) {
        let bottleKey = ProgramRunLogStore.bottleKey(for: bottle)
        guard let record = store.record(bottleKey: bottleKey),
              record.recipeID == recipeID else { return }
        store.remove(bottleKey: bottleKey)
    }

    private static func registryKey(_ entry: RegistryEntry) -> String {
        "\(entry.path)|\(entry.key)"
    }

    // MARK: - Default runners

    private static let defaultVerbRunner: VerbRunner = { verb, bottle in
        let engine = engine(for: bottle)
        let winetricks = engine.libraryRoot.appending(path: "winetricks")
        guard FileManager.default.isExecutableFile(atPath: winetricks.path) else {
            throw RecipeProvisioningError.winetricksUnavailable(winetricks)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = bottle.url.path(percentEncoded: false)
        environment["WINE"] = engine.wineBinary.path(percentEncoded: false)
        environment["WINEDEBUG"] = "-all"
        let bin = engine.wineBinary.deletingLastPathComponent().path(percentEncoded: false)
        environment["PATH"] = "\(bin):/usr/bin:/bin:/usr/sbin:/sbin"

        let result = try await ProcessRunner.run(
            executable: winetricks,
            arguments: [verb],
            environment: environment
        )
        guard result.isSuccess else {
            throw RecipeProvisioningError.verbFailed(
                verb: verb,
                output: result.standardOutputString + "\n" + result.standardErrorString
            )
        }
        Logger.wineKit.info("RecipeProvisioner: winetricks \(verb) complete")
    }

    private static let defaultRegistryRunner: RegistryRunner = { entry, bottle in
        let engine = engine(for: bottle)
        let result = try await Wine.runWine(
            [
                "reg", "add", entry.path,
                "/v", entry.key,
                "/t", entry.type.rawValue,
                "/d", entry.value,
                "/f"
            ],
            bottle: bottle,
            engine: engine
        )
        if result.localizedCaseInsensitiveContains("error") {
            throw RecipeProvisioningError.registryFailed(entry: entry, output: result)
        }
        Logger.wineKit.info("RecipeProvisioner: registry \(entry.path)\\\(entry.key) written")
    }

    private static func engine(for bottle: Bottle) -> any WineEngine {
        if let id = bottle.settings.engineID,
           let engine = WineEngineCatalog.engine(id: id),
           engine.isInstalled() {
            return engine
        }
        return WineEngineRegistry.shared.current
    }
}
