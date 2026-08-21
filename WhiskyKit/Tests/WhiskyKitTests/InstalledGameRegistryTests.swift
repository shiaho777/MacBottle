//
//  InstalledGameRegistryTests.swift
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

final class InstalledGameRegistryTests: XCTestCase {

    private func makeTempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "macbottle-registry-\(UUID().uuidString)")
            .appending(path: "installed-games.json")
    }

    private func makeGame(recipeID: String) -> InstalledGame {
        InstalledGame(
            recipeID: recipeID,
            bottleURL: URL(fileURLWithPath: "/tmp/bottles/\(recipeID)"),
            mainExe: "C:\\game.exe"
        )
    }

    func testRecordRoundTripAndRemove() throws {
        let storeURL = makeTempStoreURL()
        let registry = InstalledGameRegistry(storeURL: storeURL)

        try registry.record(makeGame(recipeID: "steam.1"))
        try registry.record(makeGame(recipeID: "steam.2"))
        XCTAssertEqual(registry.all().map(\.recipeID).sorted(), ["steam.1", "steam.2"])

        try registry.remove(recipeID: "steam.1")
        XCTAssertEqual(registry.all().map(\.recipeID), ["steam.2"])
    }

    func testCorruptStoreIsQuarantinedNotOverwritten() throws {
        let storeURL = makeTempStoreURL()
        let registry = InstalledGameRegistry(storeURL: storeURL)
        try registry.record(makeGame(recipeID: "steam.1"))

        let garbage = "{ this is not json"
        try garbage.write(to: storeURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(registry.all().isEmpty)

        try registry.record(makeGame(recipeID: "steam.2"))

        XCTAssertEqual(registry.all().map(\.recipeID), ["steam.2"])
        let backup = storeURL.appendingPathExtension("corrupt")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), garbage)
    }
}
