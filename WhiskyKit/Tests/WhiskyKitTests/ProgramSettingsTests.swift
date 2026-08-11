//
//  ProgramSettingsTests.swift
//  Whisky
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

final class ProgramSettingsTests: XCTestCase {
    func testDefaultLaunchModeIsFile() {
        let settings = ProgramSettings()
        XCTAssertEqual(settings.launchMode, .file)
        XCTAssertEqual(settings.launchCommand, "")
    }

    func testCommandModeRoundTrip() throws {
        var settings = ProgramSettings()
        settings.launchMode = .command
        settings.launchCommand = "winecfg"

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(settings)
        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)

        XCTAssertEqual(decoded.launchMode, .command)
        XCTAssertEqual(decoded.launchCommand, "winecfg")
    }

    func testLegacyPlistWithoutLaunchModeDefaultsToFile() throws {
        let legacy: [String: Any] = [
            "locale": "",
            "environment": [String: String](),
            "arguments": "-window",
            "recipeID": "steam.123"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: legacy, format: .xml, options: 0
        )
        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)

        XCTAssertEqual(decoded.launchMode, .file)
        XCTAssertEqual(decoded.launchCommand, "")
        XCTAssertEqual(decoded.arguments, "-window")
        XCTAssertEqual(decoded.recipeID, "steam.123")
    }
}
