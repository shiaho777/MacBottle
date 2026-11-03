//
//  BottleSettingsTests.swift
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

final class BottleSettingsTests: XCTestCase {
    private var workDir: URL!
    private var metadataURL: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(component: "bottlesettings-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        metadataURL = workDir.appending(path: "Metadata.plist")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    func testMissingMetadataCreatesDefaults() throws {
        let settings = try BottleSettings.decode(from: metadataURL)
        XCTAssertEqual(settings.windowsVersion, .win10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))
    }

    func testRoundTripPreservesUserValues() throws {
        var settings = BottleSettings()
        settings.name = "My Bottle"
        settings.windowsVersion = .win11
        settings.dxvk = true
        try settings.encode(to: metadataURL)

        let loaded = try BottleSettings.decode(from: metadataURL)
        XCTAssertEqual(loaded.name, "My Bottle")
        XCTAssertEqual(loaded.windowsVersion, .win11)
        XCTAssertTrue(loaded.dxvk)
    }

    func testCorruptMetadataIsQuarantinedAndThrows() throws {
        let garbage = Data("not a plist".utf8)
        try garbage.write(to: metadataURL)

        XCTAssertThrowsError(try BottleSettings.decode(from: metadataURL))

        let backups = try FileManager.default.contentsOfDirectory(
            at: workDir,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("decode-failed") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), garbage)
    }

    func testDXVKEnvironmentIsSuppressedWhenEngineLacksDXVK() {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.dxvkAsync = true

        var unsupported: [String: String] = [:]
        settings.environmentVariables(wineEnv: &unsupported, dxvkAvailable: false)
        XCTAssertNil(unsupported["WINEDLLOVERRIDES"])
        XCTAssertNil(unsupported["DXVK_ASYNC"])

        var supported: [String: String] = [:]
        settings.environmentVariables(wineEnv: &supported, dxvkAvailable: true)
        XCTAssertEqual(supported["WINEDLLOVERRIDES"], "dxgi,d3d9,d3d10core,d3d11=n,b")
        XCTAssertEqual(supported["DXVK_ASYNC"], "1")
    }
}
