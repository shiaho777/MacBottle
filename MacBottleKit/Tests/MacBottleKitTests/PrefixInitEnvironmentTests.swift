//
//  PrefixInitEnvironmentTests.swift
//  MacBottleKit
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

@MainActor
final class PrefixInitEnvironmentTests: XCTestCase {
    private func makeBottle() throws -> (Bottle, URL) {
        let url = URL(fileURLWithPath: "/tmp/macbottle-init-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: url, inFlight: true)
        bottle.settings.name = "InitTest"
        return (bottle, url)
    }

    func testUnbootedPrefixDisablesMacDriver() throws {
        let (bottle, url) = try makeBottle()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(Wine.prefixBootComplete(bottle: bottle))
        let env = Wine.constructWineEnvironment(for: bottle)
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertTrue(overrides.contains("winemac.drv=d"))
    }

    func testBootCompletePrefixKeepsMacDriver() throws {
        let (bottle, url) = try makeBottle()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data().write(to: url.appending(path: ".update-timestamp"))
        XCTAssertTrue(Wine.prefixBootComplete(bottle: bottle))
        let env = Wine.constructWineEnvironment(for: bottle)
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertFalse(overrides.contains("winemac.drv=d"))
    }

    func testMacDriverOverrideMergesWithExistingOverrides() throws {
        let (bottle, url) = try makeBottle()
        defer { try? FileManager.default.removeItem(at: url) }

        let env = Wine.constructWineEnvironment(
            for: bottle,
            environment: ["WINEDLLOVERRIDES": "dxgi,d3d11=n,b"]
        )
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertTrue(overrides.contains("winemac.drv=d"))
        XCTAssertTrue(overrides.contains("dxgi,d3d11=n,b"))
    }
}
