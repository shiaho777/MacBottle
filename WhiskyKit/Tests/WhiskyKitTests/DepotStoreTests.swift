//
//  DepotStoreTests.swift
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
@testable import WhiskyKit

final class DepotStoreTests: XCTestCase {

    private var root: URL!
    private var store: DepotStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-depot-test-\(UUID().uuidString)")
        store = DepotStore(contentStore: ContentStore(root: root))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeManifest(appID: Int, stateFlags: String) throws {
        let steamapps = store.steamapps(appID: appID)
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        let manifest = """
        "AppState"
        {
            "appid"     "\(appID)"
            "StateFlags"  "\(stateFlags)"
        }
        """
        try manifest.write(
            to: steamapps.appending(path: "appmanifest_\(appID).acf"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func leavePartialCommonTree(appID: Int) throws {
        let common = store.steamapps(appID: appID).appending(path: "common").appending(path: "GameDir")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        try "partial".write(to: common.appending(path: "game.exe"), atomically: true, encoding: .utf8)
    }

    func testMissingDepotIsNotPresent() {
        XCTAssertFalse(store.isDepotPresent(appID: 1250))
    }

    func testCancelledDownloadLeftoversAreNotPresent() throws {
        try leavePartialCommonTree(appID: 1250)
        XCTAssertFalse(store.isDepotPresent(appID: 1250))
    }

    func testFullyInstalledManifestIsPresent() throws {
        try writeManifest(appID: 1250, stateFlags: "4")
        XCTAssertTrue(store.isDepotPresent(appID: 1250))
    }

    func testUpdateRequiredManifestIsNotPresent() throws {
        try writeManifest(appID: 1250, stateFlags: "6")
        XCTAssertFalse(store.isDepotPresent(appID: 1250))
    }

    func testFilesMissingManifestIsNotPresent() throws {
        try writeManifest(appID: 1250, stateFlags: "36")
        XCTAssertFalse(store.isDepotPresent(appID: 1250))
    }

    func testUnparsableManifestIsNotPresent() throws {
        let steamapps = store.steamapps(appID: 1250)
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try "{ truncated".write(
            to: steamapps.appending(path: "appmanifest_1250.acf"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertFalse(store.isDepotPresent(appID: 1250))
    }
}
