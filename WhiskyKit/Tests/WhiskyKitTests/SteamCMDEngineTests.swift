//
//  SteamCMDEngineTests.swift
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

final class SteamCMDEngineTests: XCTestCase {

    func testUpdateScriptCarriesLoginAndValidate() {
        let script = SteamCMDEngine.makeUpdateScript(
            appID: 2050650,
            installDir: URL(fileURLWithPath: "/tmp/library"),
            credentials: SteamCredentials(username: "user", password: "secret"),
            validate: true
        )

        XCTAssertTrue(script.contains("@sSteamCmdForcePlatformType windows"))
        XCTAssertTrue(script.contains("force_install_dir /tmp/library"))
        XCTAssertTrue(script.contains("login \"user\" \"secret\""))
        XCTAssertTrue(script.contains("app_update 2050650 validate"))
        XCTAssertTrue(script.hasSuffix("quit\n"))
    }

    func testUpdateScriptOmitsValidateWhenRequested() {
        let script = SteamCMDEngine.makeUpdateScript(
            appID: 220,
            installDir: URL(fileURLWithPath: "/tmp/library"),
            credentials: .anonymous,
            validate: false
        )

        XCTAssertTrue(script.contains("login anonymous"))
        XCTAssertTrue(script.contains("app_update 220\n"))
        XCTAssertFalse(script.contains("validate"))
    }

    func testUpdateScriptQuotesCredentialsWithMetacharacters() {
        let script = SteamCMDEngine.makeUpdateScript(
            appID: 220,
            installDir: URL(fileURLWithPath: "/tmp/library"),
            credentials: SteamCredentials(
                username: "user",
                password: "pa \"ss\" \\word pass"
            ),
            validate: false
        )

        XCTAssertTrue(script.contains("login \"user\" \"pa \\\"ss\\\" \\\\word pass\""))
    }

    func testUpdateScriptIncludesGuardCodeOnlyForNamedAccounts() {
        let named = SteamCMDEngine.makeUpdateScript(
            appID: 220,
            installDir: URL(fileURLWithPath: "/tmp/library"),
            credentials: SteamCredentials(username: "user", password: "secret", steamGuardCode: "12345"),
            validate: false
        )
        XCTAssertTrue(named.contains("set_steam_guard_code \"12345\""))

        let anonymousWithCode = SteamCMDEngine.makeUpdateScript(
            appID: 220,
            installDir: URL(fileURLWithPath: "/tmp/library"),
            credentials: SteamCredentials(username: "anonymous", password: "", steamGuardCode: "12345"),
            validate: false
        )
        XCTAssertFalse(anonymousWithCode.contains("set_steam_guard_code"))
    }
}
