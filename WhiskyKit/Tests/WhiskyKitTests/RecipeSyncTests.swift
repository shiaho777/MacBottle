//
//  RecipeSyncTests.swift
//  WhiskyKitTests
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
import XCTest
@testable import WhiskyKit

final class RecipeSyncTests: XCTestCase {

    // MARK: - Diff

    func testDiffFirstSyncTreatsEverythingAsAdded() {
        let remote = RecipeIndex(
            generatedAt: "2026-05-12T00:00:00Z",
            recipes: [
                .init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10),
                .init(id: "steam.2", path: "steam/2.json", sha: "b", size: 20)
            ]
        )
        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: nil, knownRecipes: [:]
        )
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.allSatisfy { $0.kind == .added })
        XCTAssertEqual(changes.map(\.id), ["steam.1", "steam.2"])
    }

    func testDiffDetectsAddedRemovedAndUpdated() {
        let remote = RecipeIndex(
            generatedAt: "2026-05-12T00:00:00Z",
            recipes: [
                .init(id: "steam.1", path: "steam/1.json", sha: "a-new", size: 10),
                .init(id: "steam.3", path: "steam/3.json", sha: "c", size: 30)
            ]
        )
        let local: [RecipeIndex.Entry] = [
            .init(id: "steam.1", path: "steam/1.json", sha: "a-old", size: 10),
            .init(id: "steam.2", path: "steam/2.json", sha: "b", size: 20)
        ]

        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: local, knownRecipes: [:]
        )

        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes[0].kind, .added)    // steam.3
        XCTAssertEqual(changes[0].id, "steam.3")
        XCTAssertEqual(changes[1].kind, .updated)  // steam.1 sha changed
        XCTAssertEqual(changes[1].id, "steam.1")
        XCTAssertEqual(changes[2].kind, .removed)  // steam.2 gone remotely
        XCTAssertEqual(changes[2].id, "steam.2")
    }

    func testDiffIsEmptyWhenNothingChanged() {
        let entries: [RecipeIndex.Entry] = [
            .init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)
        ]
        let remote = RecipeIndex(generatedAt: "now", recipes: entries)

        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: entries, knownRecipes: [:]
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testDiffEnrichesChangesWithKnownRecipeMetadata() {
        let remote = RecipeIndex(
            generatedAt: "now",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
        )
        let known: Recipe = Recipe(
            id: "steam.1", title: "Terraria",
            iconURL: URL(string: "https://example.com/t.jpg"),
            dxVersion: .d3d9, minMacOS: "14.0",
            renderer: .wined3d, compatibility: .platinum
        )
        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: nil, knownRecipes: ["steam.1": known]
        )
        XCTAssertEqual(changes.first?.title, "Terraria")
        XCTAssertEqual(changes.first?.iconURL?.host, "example.com")
    }

    // MARK: - Cache

    func testCacheRoundTripsRecipes() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = RecipeCache(root: temp)
        let recipe = Recipe(
            id: "steam.9999", title: "TestGame",
            dxVersion: .d3d11, minMacOS: "14.0",
            renderer: .d3dmetal, compatibility: .gold
        )
        try cache.storeRecipe(recipe)

        XCTAssertEqual(cache.loadRecipe(id: "steam.9999")?.title, "TestGame")
        XCTAssertEqual(cache.loadAll().count, 1)

        try cache.removeRecipe(id: "steam.9999")
        XCTAssertNil(cache.loadRecipe(id: "steam.9999"))
        XCTAssertTrue(cache.loadAll().isEmpty)
    }

    func testCacheMetaPersistsAcrossInstances() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache1 = RecipeCache(root: temp)
        let meta = RecipeCache.Meta(
            etag: "W/\"abc\"",
            index: RecipeIndex(
                generatedAt: "2026-05-12T00:00:00Z",
                recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
            ),
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try cache1.saveMeta(meta)

        // A fresh cache instance pointed at the same root must see the
        // same meta. This is the persistence guarantee the sync engine
        // depends on across app launches.
        let cache2 = RecipeCache(root: temp)
        let loaded = cache2.loadMeta()
        XCTAssertEqual(loaded.etag, "W/\"abc\"")
        XCTAssertEqual(loaded.index?.recipes.count, 1)
        XCTAssertEqual(loaded.lastSyncAt, meta.lastSyncAt)
    }

    // MARK: - Source with stub fetcher

    func testSourceDecodesIndexFromFetcher() async throws {
        let index = RecipeIndex(
            generatedAt: "now",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
        )
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder().encode(index)

        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { _, _ in (data, "W/\"v1\"") }
        )
        let (fetched, etag) = try await source.fetchIndex(previousETag: nil)
        XCTAssertEqual(fetched.recipes.count, 1)
        XCTAssertEqual(etag, "W/\"v1\"")
    }

    func testSourceSurfacesNotModified() async {
        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { _, _ in throw RemoteRecipeError.notModified }
        )
        do {
            _ = try await source.fetchIndex(previousETag: "W/\"v1\"")
            XCTFail("expected notModified")
        } catch RemoteRecipeError.notModified {
            // pass
        } catch {
            XCTFail("got unexpected error: \(error)")
        }
    }

    func testDiffToleratesDuplicateIDsInRemoteIndex() {
        let remote = RecipeIndex(
            generatedAt: "now",
            recipes: [
                .init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10),
                .init(id: "steam.1", path: "steam/1-dup.json", sha: "b", size: 20),
                .init(id: "steam.2", path: "steam/2.json", sha: "c", size: 30)
            ]
        )
        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: nil, knownRecipes: [:]
        )
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.map(\.id), ["steam.1", "steam.2"])
    }

    func testDiffToleratesDuplicateIDsInLocalEntries() {
        let remote = RecipeIndex(
            generatedAt: "now",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
        )
        let local: [RecipeIndex.Entry] = [
            .init(id: "steam.1", path: "steam/1.json", sha: "old", size: 10),
            .init(id: "steam.1", path: "steam/1-dup.json", sha: "old2", size: 10)
        ]

        let changes = RecipeSyncDiff.compute(
            remoteIndex: remote, localEntries: local, knownRecipes: [:]
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].kind, .updated)
        XCTAssertEqual(changes[0].id, "steam.1")
    }

    // MARK: - Service end-to-end with stubs

    func testServiceAppliesAddAndRemoveAtomically() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-svc-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = seedCacheWithStaleEntry(at: temp)
        let (indexData, recipeData) = buildRemoteFixtures()
        let source = stubSource(indexData: indexData, recipeData: recipeData)

        let service = RecipeSyncService(source: source, cache: cache)
        let check = try await service.check(knownRecipes: [:])
        XCTAssertEqual(check.changes.count, 2)

        let outcomes = try await service.apply(
            changes: check.changes,
            remoteIndex: check.remoteIndex,
            newETag: check.newETag
        )
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertTrue(outcomes.allSatisfy(\.success))

        XCTAssertNotNil(cache.loadRecipe(id: "steam.1"))
        XCTAssertNil(cache.loadRecipe(id: "steam.2"))
        let meta = cache.loadMeta()
        XCTAssertEqual(meta.etag, "W/\"new\"")
        XCTAssertEqual(meta.index?.recipes.map(\.id), ["steam.1"])
    }

    func testServiceSubsetApplyKeepsUnselectedChangesPending() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-svc-subset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = RecipeCache(root: temp)
        let remote = RecipeIndex(
            generatedAt: "new",
            recipes: [
                .init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10),
                .init(id: "steam.2", path: "steam/2.json", sha: "b", size: 20)
            ]
        )
        let service = stubbedService(
            cache: cache,
            index: remote,
            recipesByFile: [
                "1.json": Recipe(
                    id: "steam.1", title: "One",
                    dxVersion: .d3d11, minMacOS: "14.0",
                    renderer: .d3dmetal, compatibility: .gold
                ),
                "2.json": Recipe(
                    id: "steam.2", title: "Two",
                    dxVersion: .d3d11, minMacOS: "14.0",
                    renderer: .d3dmetal, compatibility: .gold
                )
            ]
        )

        let check = try await service.check(knownRecipes: [:])
        XCTAssertEqual(check.changes.count, 2)

        let outcomes = try await service.apply(
            changes: check.changes.filter { $0.id == "steam.1" },
            remoteIndex: check.remoteIndex,
            newETag: check.newETag
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(outcomes[0].success)

        XCTAssertNotNil(cache.loadRecipe(id: "steam.1"))
        XCTAssertNil(cache.loadRecipe(id: "steam.2"))

        let meta = cache.loadMeta()
        XCTAssertEqual(meta.index?.recipes.map(\.id), ["steam.1"])
        XCTAssertNil(meta.etag)

        let second = try await service.check(knownRecipes: [:])
        XCTAssertEqual(second.changes.map(\.id), ["steam.2"])
        XCTAssertEqual(second.changes[0].kind, .added)
    }

    func testServicePartialFailureKeepsFailedEntryPending() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-svc-partial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = RecipeCache(root: temp)
        let remote = RecipeIndex(
            generatedAt: "new",
            recipes: [
                .init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10),
                .init(id: "steam.2", path: "steam/2.json", sha: "b", size: 20)
            ]
        )
        let service = stubbedService(
            cache: cache,
            index: remote,
            recipesByFile: [
                "1.json": Recipe(
                    id: "steam.1", title: "One",
                    dxVersion: .d3d11, minMacOS: "14.0",
                    renderer: .d3dmetal, compatibility: .gold
                ),
                "2.json": Recipe(
                    id: "steam.2", title: "Two",
                    dxVersion: .d3d11, minMacOS: "14.0",
                    renderer: .d3dmetal, compatibility: .gold
                )
            ],
            failingFiles: ["2.json"]
        )

        let check = try await service.check(knownRecipes: [:])
        let outcomes = try await service.apply(
            changes: check.changes,
            remoteIndex: check.remoteIndex,
            newETag: check.newETag
        )
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes.filter { $0.success }.count, 1)

        let meta = cache.loadMeta()
        XCTAssertEqual(meta.index?.recipes.map(\.id), ["steam.1"])
        XCTAssertNil(meta.etag)

        let second = try await service.check(knownRecipes: [:])
        XCTAssertEqual(second.changes.map(\.id), ["steam.2"])
        XCTAssertEqual(second.changes[0].kind, .added)
    }

    func testServiceRejectsRecipeIDMismatch() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-svc-mismatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = RecipeCache(root: temp)
        let remote = RecipeIndex(
            generatedAt: "new",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "a", size: 10)]
        )
        let service = stubbedService(
            cache: cache,
            index: remote,
            recipesByFile: [
                "1.json": Recipe(
                    id: "steam.other", title: "Impostor",
                    dxVersion: .d3d11, minMacOS: "14.0",
                    renderer: .d3dmetal, compatibility: .gold
                )
            ]
        )

        let check = try await service.check(knownRecipes: [:])
        let outcomes = try await service.apply(
            changes: check.changes,
            remoteIndex: check.remoteIndex,
            newETag: check.newETag
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertFalse(outcomes[0].success)

        XCTAssertNil(cache.loadRecipe(id: "steam.other"))
        let meta = cache.loadMeta()
        XCTAssertNil(meta.index)
        XCTAssertNil(meta.etag)
    }

    // MARK: - Checksum verification

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeRecipe(id: String) -> Recipe {
        Recipe(
            id: id, title: "One",
            dxVersion: .d3d11, minMacOS: "14.0",
            renderer: .d3dmetal, compatibility: .gold
        )
    }

    func testEntryRoundTripsOptionalSHA256() throws {
        let withDigest = RecipeIndex.Entry(
            id: "steam.1", path: "steam/1.json", sha: "a", size: 10,
            sha256: "abc123"
        )
        let withoutDigest = RecipeIndex.Entry(
            id: "steam.1", path: "steam/1.json", sha: "a", size: 10
        )

        let encodedWith = try JSONEncoder().encode(withDigest)
        XCTAssertNotNil(String(data: encodedWith, encoding: .utf8))
        XCTAssertTrue(
            String(data: encodedWith, encoding: .utf8)?.contains("sha256") ?? false
        )
        XCTAssertEqual(
            try JSONDecoder().decode(RecipeIndex.Entry.self, from: encodedWith),
            withDigest
        )

        let encodedWithout = try JSONEncoder().encode(withoutDigest)
        XCTAssertTrue(
            String(data: encodedWithout, encoding: .utf8)?.contains("sha256") != true
        )
        XCTAssertEqual(
            try JSONDecoder().decode(RecipeIndex.Entry.self, from: encodedWithout),
            withoutDigest
        )
    }

    func testFetchRecipeAcceptsBytesMatchingDigest() async throws {
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder().encode(makeRecipe(id: "steam.1"))
        let entry = RecipeIndex.Entry(
            id: "steam.1", path: "steam/1.json", sha: "a", size: data.count,
            sha256: Self.sha256Hex(data)
        )
        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { _, _ in (data, nil) }
        )

        let fetched = try await source.fetchRecipe(entry)
        XCTAssertEqual(fetched.id, "steam.1")
    }

    func testFetchRecipeRejectsCorruptedBytesBeforeDecoding() async {
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder().encode(makeRecipe(id: "steam.1"))
        let entry = RecipeIndex.Entry(
            id: "steam.1", path: "steam/1.json", sha: "a", size: data.count,
            sha256: Self.sha256Hex(data)
        )
        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { _, _ in (data.dropLast(), nil) }
        )

        do {
            _ = try await source.fetchRecipe(entry)
            XCTFail("expected checksum mismatch")
        } catch let error as RemoteRecipeError {
            guard case .recipeChecksumMismatch = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testFetchRecipeSkipsVerificationWhenDigestAbsent() async throws {
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder().encode(makeRecipe(id: "steam.1"))
        let entry = RecipeIndex.Entry(
            id: "steam.1", path: "steam/1.json", sha: "a", size: data.count
        )
        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { _, _ in (data, nil) }
        )

        let fetched = try await source.fetchRecipe(entry)
        XCTAssertEqual(fetched.id, "steam.1")
    }

    func testServiceApplyFailsOnChecksumMismatch() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-svc-checksum-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let cache = RecipeCache(root: temp)
        // swiftlint:disable:next force_try
        let recipeData = try! JSONEncoder().encode(makeRecipe(id: "steam.1"))
        let wrongDigest = Self.sha256Hex(Data("other bytes".utf8))
        let remote = RecipeIndex(
            generatedAt: "new",
            recipes: [
                .init(
                    id: "steam.1", path: "steam/1.json", sha: "a",
                    size: recipeData.count, sha256: wrongDigest
                )
            ]
        )
        // swiftlint:disable:next force_try
        let indexData = try! JSONEncoder().encode(remote)
        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { url, _ in
                url.lastPathComponent == "_index.json"
                    ? (indexData, "W/\"new\"")
                    : (recipeData, nil)
            }
        )
        let service = RecipeSyncService(source: source, cache: cache)

        let check = try await service.check(knownRecipes: [:])
        let outcomes = try await service.apply(
            changes: check.changes,
            remoteIndex: check.remoteIndex,
            newETag: check.newETag
        )

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertFalse(outcomes[0].success)
        guard case .recipeChecksumMismatch = outcomes[0].error as? RemoteRecipeError else {
            XCTFail("expected checksum mismatch, got \(String(describing: outcomes[0].error))")
            return
        }

        XCTAssertNil(cache.loadRecipe(id: "steam.1"))
        let meta = cache.loadMeta()
        XCTAssertNil(meta.index)
        XCTAssertNil(meta.etag)

        let second = try await service.check(knownRecipes: [:])
        XCTAssertEqual(second.changes.map(\.kind), [.added])
    }

    // MARK: Fixture helpers

    private func seedCacheWithStaleEntry(at root: URL) -> RecipeCache {
        let cache = RecipeCache(root: root)
        let stale = Recipe(
            id: "steam.2", title: "Stale",
            dxVersion: .d3d11, minMacOS: "14.0",
            renderer: .d3dmetal, compatibility: .gold
        )
        // swiftlint:disable:next force_try
        try! cache.storeRecipe(stale)
        // swiftlint:disable:next force_try
        try! cache.saveMeta(.init(
            etag: "W/\"old\"",
            index: RecipeIndex(
                generatedAt: "old",
                recipes: [.init(id: "steam.2", path: "steam/2.json", sha: "s1", size: 10)]
            ),
            lastSyncAt: Date.distantPast
        ))
        return cache
    }

    private func buildRemoteFixtures() -> (indexData: Data, recipeData: Data) {
        let newIndex = RecipeIndex(
            generatedAt: "new",
            recipes: [.init(id: "steam.1", path: "steam/1.json", sha: "n1", size: 20)]
        )
        let newRecipe = Recipe(
            id: "steam.1", title: "Fresh",
            dxVersion: .d3d11, minMacOS: "14.0",
            renderer: .d3dmetal, compatibility: .gold
        )
        // swiftlint:disable force_try
        return (try! JSONEncoder().encode(newIndex),
                try! JSONEncoder().encode(newRecipe))
        // swiftlint:enable force_try
    }

    private func stubSource(indexData: Data, recipeData: Data) -> RemoteRecipeSource {
        RemoteRecipeSource(
            configuration: .init(),
            fetcher: { url, _ in
                if url.lastPathComponent == "_index.json" {
                    return (indexData, "W/\"new\"")
                }
                return (recipeData, nil)
            }
        )
    }

    private func stubbedService(
        cache: RecipeCache,
        index: RecipeIndex,
        recipesByFile: [String: Recipe],
        failingFiles: Set<String> = []
    ) -> RecipeSyncService {
        // swiftlint:disable force_try
        let indexData = try! JSONEncoder().encode(index)
        let recipeDataByFile = recipesByFile.mapValues { try! JSONEncoder().encode($0) }
        // swiftlint:enable force_try
        let source = RemoteRecipeSource(
            configuration: .init(),
            fetcher: { url, _ in
                if url.lastPathComponent == "_index.json" {
                    return (indexData, "W/\"new\"")
                }
                if failingFiles.contains(url.lastPathComponent) {
                    throw NSError(
                        domain: "RecipeSyncTests", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "network down"]
                    )
                }
                guard let data = recipeDataByFile[url.lastPathComponent] else {
                    throw NSError(
                        domain: "RecipeSyncTests", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "no fixture for \(url.lastPathComponent)"]
                    )
                }
                return (data, nil)
            }
        )
        return RecipeSyncService(source: source, cache: cache)
    }
}
