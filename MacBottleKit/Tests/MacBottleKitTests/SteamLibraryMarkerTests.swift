//
//  SteamLibraryMarkerTests.swift
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

final class SteamLibraryMarkerTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "steam-marker-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeBottle(_ name: String) throws -> Bottle {
        let url = workDir.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: url, inFlight: true)
        bottle.isAvailable = true
        return bottle
    }

    func testMarkAndFind() throws {
        let plain = try makeBottle("plain")
        let shared = try makeBottle("shared")
        XCTAssertFalse(SteamLibraryMarker.isMarked(shared))
        try SteamLibraryMarker.mark(shared)
        XCTAssertTrue(SteamLibraryMarker.isMarked(shared))
        XCTAssertEqual(SteamLibraryMarker.find(in: [plain, shared]), shared)
    }

    func testFindIgnoresUnavailableBottles() throws {
        let shared = try makeBottle("shared")
        try SteamLibraryMarker.mark(shared)
        shared.isAvailable = false
        XCTAssertNil(SteamLibraryMarker.find(in: [shared]))
    }
}
