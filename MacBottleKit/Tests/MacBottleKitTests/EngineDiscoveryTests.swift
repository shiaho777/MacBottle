//
//  EngineDiscoveryTests.swift
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

import SemanticVersion
import XCTest
@testable import MacBottleKit

final class EngineDiscoveryTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appending(path: "engine-discovery-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeEngine(named name: String, valid: Bool) throws {
        let engine = root.appending(path: name)
        let bin = engine.appending(path: "Wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let wine = bin.appending(path: "wine64")
        try Data().write(to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)

        let unix = engine.appending(path: "Wine/lib/wine/aarch64-unix")
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)

        if valid {
            let plist = engine.appending(path: "WhiskyWineVersion.plist")
            let data = try PropertyListEncoder().encode(
                EngineVersionInfo(version: SemanticVersion(1, 2, 3))
            )
            try data.write(to: plist)
        }
    }

    func testDiscoversValidEngineDirectoriesOnly() throws {
        try makeEngine(named: "local-wine", valid: true)
        try makeEngine(named: "no-version", valid: false)

        let engines = WineEngineCatalog.discoveredEngines(in: root)
        XCTAssertEqual(engines.map(\.identifier), ["local-wine"])
        XCTAssertEqual(engines.first?.displayName, "local-wine")
        XCTAssertEqual(engines.first?.installedVersion(), SemanticVersion(1, 2, 3))
    }

    func testIgnoresStagingAndOldDirectories() throws {
        try makeEngine(named: "candidate.staging-deadbeef", valid: true)
        try makeEngine(named: "candidate.old-deadbeef", valid: true)
        XCTAssertTrue(WineEngineCatalog.discoveredEngines(in: root).isEmpty)
    }
}
