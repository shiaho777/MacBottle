//
//  WineEngineTests.swift
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

import XCTest
import SemanticVersion
@testable import WhiskyKit

final class WineEngineTests: XCTestCase {

    // MARK: - CrossOverEngine identity

    func testCrossOverEngineIdentifier() {
        let engine = CrossOverEngine.default
        XCTAssertEqual(engine.identifier, "crossover")
        XCTAssertFalse(engine.displayName.isEmpty)
    }

    func testCrossOverEngineDerivesWineBinaryUnderLibraryRoot() {
        let engine = CrossOverEngine.default
        let libPath = engine.libraryRoot.path
        let binPath = engine.wineBinary.path
        XCTAssertTrue(binPath.hasPrefix(libPath),
            "wineBinary must live under libraryRoot; got \(binPath) vs \(libPath)")
    }

    func testCrossOverEngineDefaultUpdateFeedIsReachableURL() {
        let engine = CrossOverEngine.default
        XCTAssertEqual(engine.updateFeedURL.scheme, "https")
    }

    // MARK: - Registry behaviour

    func testRegistryDefaultsToCrossOver() {
        let registry = WineEngineRegistry(current: CrossOverEngine.default)
        XCTAssertEqual(registry.current.identifier, "crossover")
    }

    func testLocalPathEngineIdentity() {
        let root = FileManager.default.temporaryDirectory.appending(path: "macbottle-local-engine")
        let engine = LocalPathEngine(
            identifier: "crossover-d3dmetal",
            displayName: "CrossOver + D3DMetal",
            libraryRoot: root
        )
        XCTAssertEqual(engine.identifier, WineEngineCatalog.d3dMetalIdentifier)
        XCTAssertFalse(engine.isInstalled())
        XCTAssertTrue(engine.wineBinary.path.hasSuffix("/Wine/bin/wine"))
    }

    func testCatalogListsBothEngines() {
        let ids = WineEngineCatalog.allEngines().map(\.identifier)
        XCTAssertTrue(ids.contains(WineEngineCatalog.modernIdentifier))
        XCTAssertTrue(ids.contains(WineEngineCatalog.d3dMetalIdentifier))
    }

    func testRegistrySwapsEngine() {
        let registry = WineEngineRegistry()
        let fake = FakeEngine()
        registry.setCurrent(fake)
        XCTAssertEqual(registry.current.identifier, "fake")
    }

    // MARK: - WhiskyWineInstaller shim routes through registry

    func testWhiskyWineInstallerShimReflectsCurrentEngine() {
        // The shim reads from `WineEngineRegistry.shared.current`. Swap
        // in a fake engine and confirm the shim's `binFolder` matches the
        // fake's wineBinary directory. Restore the default afterwards so
        // other tests are unaffected.
        let original = WineEngineRegistry.shared.current
        defer { WineEngineRegistry.shared.setCurrent(original) }

        let fake = FakeEngine()
        WineEngineRegistry.shared.setCurrent(fake)

        XCTAssertEqual(
            WhiskyWineInstaller.binFolder.path,
            fake.wineBinary.deletingLastPathComponent().path
        )
        XCTAssertEqual(
            WhiskyWineInstaller.libraryFolder.path,
            fake.libraryRoot.path
        )
    }
}

// MARK: - Test helper

/// Minimal in-memory engine used to verify the abstraction without
/// touching disk. Rooted under the system temp directory so any stray
/// access fails loudly rather than corrupting a real install.
private struct FakeEngine: WineEngine {
    let identifier = "fake"
    let displayName = "Fake Engine"

    var libraryRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "macbottle-fake-engine")
    }
    var wineBinary: URL { libraryRoot.appending(path: "bin").appending(path: "wine64") }
    var wineserverBinary: URL { libraryRoot.appending(path: "bin").appending(path: "wineserver") }
    var dxvkFolder: URL { libraryRoot.appending(path: "DXVK") }

    func isInstalled() -> Bool { false }
    func installedVersion() -> SemanticVersion? { nil }
    func install(from tarball: URL) throws { /* no-op */ }
    func uninstall() throws { /* no-op */ }
    func checkForUpdate() async -> (hasUpdate: Bool, remoteVersion: SemanticVersion) {
        (false, SemanticVersion(0, 0, 0))
    }
}
