//
//  DisplayPolicyTests.swift
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

final class DisplayPolicyTests: XCTestCase {
    func testRegistryUpsertStringAndDword() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "MacBottleRegistryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let reg = temp.appending(path: "user.reg")
        try """
        WINE REGISTRY Version 2
        ;; test

        [Control Panel\\\\Desktop] 1
        \"LogPixels\"=dword:000000c0

        """.write(to: reg, atomically: true, encoding: .utf8)

        let bottle = Bottle(bottleUrl: temp, inFlight: false)
        XCTAssertEqual(
            WineRegistryFile.dwordValue(bottle: bottle, keyPath: #"Control Panel\\Desktop"#, name: "LogPixels"),
            192
        )

        XCTAssertTrue(try WineRegistryFile.setDwordValue(
            bottle: bottle,
            keyPath: #"Control Panel\\Desktop"#,
            name: "LogPixels",
            value: 96
        ))
        XCTAssertEqual(
            WineRegistryFile.dwordValue(bottle: bottle, keyPath: #"Control Panel\\Desktop"#, name: "LogPixels"),
            96
        )

        XCTAssertTrue(try WineRegistryFile.setStringValue(
            bottle: bottle,
            keyPath: #"Software\\Wine\\Mac Driver"#,
            name: "RetinaMode",
            value: "n"
        ))
        XCTAssertEqual(
            WineRegistryFile.stringValue(
                bottle: bottle,
                keyPath: #"Software\\Wine\\Mac Driver"#,
                name: "RetinaMode"
            ),
            "n"
        )
        XCTAssertFalse(try WineRegistryFile.setStringValue(
            bottle: bottle,
            keyPath: #"Software\\Wine\\Mac Driver"#,
            name: "RetinaMode",
            value: "n"
        ))
    }

    func testClassic32EnvironmentKeepsModernDefaults() {
        let env = RuntimeLaunchOptimizer.environment(
            profile: .classic32,
            bottleDXVKEnabled: false,
            base: ["WINEPREFIX": "/tmp"]
        )
        XCTAssertEqual(env["WINEDEBUG"], "-all")
        XCTAssertEqual(env["WINE_DISABLE_KERNEL_WRITEWATCH"], "1")
    }

    func testD3DMetalProbeDoesNotCrash() {
        let status = D3DMetalCapability.probe()
        XCTAssertFalse(status.summary.isEmpty)
    }
}
