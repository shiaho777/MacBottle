//
//  BottleDataTests.swift
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

import XCTest
@testable import MacBottleKit

final class BottleDataTests: XCTestCase {
    private var workDir: URL!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(component: "bottledata-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        storeURL = workDir.appending(path: "BottleVM.plist")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    func testMissingStoreCreatesEmptyFile() {
        let data = BottleData(storeURL: storeURL)
        XCTAssertTrue(data.paths.isEmpty)
        XCTAssertFalse(data.recoveredFromCorruptStore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testPathsPersistAndReload() {
        var data = BottleData(storeURL: storeURL)
        let bottle = workDir.appending(path: "bottle-a")
        data.paths.append(bottle)

        let reloaded = BottleData(storeURL: storeURL)
        XCTAssertEqual(reloaded.paths, [bottle])
    }

    func testCorruptStoreIsQuarantinedNotOverwrittenWithNothing() throws {
        let garbage = Data("this is not a plist".utf8)
        try garbage.write(to: storeURL)

        let data = BottleData(storeURL: storeURL)

        XCTAssertTrue(data.recoveredFromCorruptStore)
        XCTAssertTrue(data.paths.isEmpty)

        let backups = try FileManager.default.contentsOfDirectory(
            at: workDir,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("decode-failed") }
        XCTAssertEqual(backups.count, 1, "the unreadable store must be preserved")
        XCTAssertEqual(try Data(contentsOf: backups[0]), garbage)
    }

    @MainActor
    func testSettingsSnapshotFollowsSettings() {
        let url = workDir.appending(path: "bottle-snapshot")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: url, inFlight: true)
        XCTAssertEqual(bottle.settingsSnapshot.name, bottle.settings.name)

        bottle.settings.name = "Renamed"
        XCTAssertEqual(bottle.settingsSnapshot.name, "Renamed")

        bottle.settings.pins.append(PinnedProgram(name: "Pin", url: url))
        XCTAssertEqual(bottle.settingsSnapshot.pins.count, bottle.settings.pins.count)
    }

    func testRecoveredStoreIsUsableAndPersistsNewPaths() {
        try? Data("broken".utf8).write(to: storeURL)
        var data = BottleData(storeURL: storeURL)
        XCTAssertTrue(data.recoveredFromCorruptStore)

        let bottle = workDir.appending(path: "bottle-b")
        data.paths.append(bottle)

        let reloaded = BottleData(storeURL: storeURL)
        XCTAssertEqual(reloaded.paths, [bottle])
    }
}
