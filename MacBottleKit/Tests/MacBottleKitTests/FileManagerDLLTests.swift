//
//  FileManagerDLLTests.swift
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

final class FileManagerDLLTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "dll-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = workDir.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testOriginalSnapshotSurvivesEngineUpgradeAndRestores() throws {
        let system32 = try makeDirectory("system32")
        let dxvk1 = try makeDirectory("dxvk1")
        let dxvk2 = try makeDirectory("dxvk2")
        let active = system32.appending(path: "d3d11.dll")
        let backup = active.appendingPathExtension("orig")

        try write("wine-original", to: active)
        try write("dxvk-v1", to: dxvk1.appending(path: "d3d11.dll"))
        try write("dxvk-v2", to: dxvk2.appending(path: "d3d11.dll"))

        try FileManager.default.replaceDLLs(in: system32, withContentsIn: dxvk1, makeOriginalCopy: true)
        XCTAssertEqual(try read(active), "dxvk-v1")
        XCTAssertEqual(try read(backup), "wine-original")

        // Installing a newer DXVK must not overwrite the pristine Wine
        // DLL with the previous DXVK version.
        try FileManager.default.replaceDLLs(in: system32, withContentsIn: dxvk2, makeOriginalCopy: true)
        XCTAssertEqual(try read(active), "dxvk-v2")
        XCTAssertEqual(try read(backup), "wine-original")

        let restored = try FileManager.default.restoreDLLs(in: system32)
        XCTAssertEqual(restored, 1)
        XCTAssertEqual(try read(active), "wine-original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testRestoreIsNoOpWithoutSnapshots() throws {
        let system32 = try makeDirectory("system32")
        XCTAssertEqual(try FileManager.default.restoreDLLs(in: system32), 0)
    }
}
