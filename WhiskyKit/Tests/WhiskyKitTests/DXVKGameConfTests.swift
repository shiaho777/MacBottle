//
//  DXVKGameConfTests.swift
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
@testable import WhiskyKit

final class DXVKGameConfTests: XCTestCase {
    private var workDir: URL!
    private var exeURL: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(component: "dxvk-conf-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        exeURL = workDir.appending(component: "game.exe")
        try? Data().write(to: exeURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private var confURL: URL {
        workDir.appending(component: "game.exe.conf")
    }

    func testResponsivePostureLatencyOne() {
        let posture = DXVKGameConf.Posture.responsive(physicalMemoryBytes: 24_000_000_000)
        XCTAssertEqual(posture.maxFrameLatency, 1)
        let memory = posture.maxDeviceMemoryMegabytes
        XCTAssertTrue(memory >= 8_192 && memory <= 24_000, "budget \(memory) outside clamp")
    }

    func testApplyWritesAllFourLevers() throws {
        DXVKGameConf.apply(
            posture: .init(maxFrameLatency: 1, maxDeviceMemoryMegabytes: 12_288),
            executable: exeURL
        )
        let text = try String(contentsOf: confURL, encoding: .utf8)
        XCTAssertTrue(text.contains("dxgi.maxFrameLatency = 1"))
        XCTAssertTrue(text.contains("d3d9.maxFrameLatency = 1"))
        XCTAssertTrue(text.contains("dxgi.maxDeviceMemory = 12288"))
        XCTAssertTrue(text.contains("dxgi.maxSharedMemory = 12288"))
    }

    func testApplyIsIdempotent() throws {
        let posture = DXVKGameConf.Posture(maxFrameLatency: 1, maxDeviceMemoryMegabytes: 12_288)
        XCTAssertTrue(DXVKGameConf.apply(posture: posture, executable: exeURL))
        XCTAssertFalse(DXVKGameConf.apply(posture: posture, executable: exeURL), "second write should be a no-op")
    }

    func testUpsertReplacesCommentedDefault() throws {
        let text = """
        # dxgi.maxFrameLatency = 0
        # other comment
        """
        try text.write(to: confURL, atomically: true, encoding: .utf8)
        let merged = DXVKGameConf.upsertLine(
            in: text,
            key: "dxgi.maxFrameLatency",
            line: "dxgi.maxFrameLatency = 1"
        )
        XCTAssertTrue(merged.contains("dxgi.maxFrameLatency = 1"))
        XCTAssertFalse(merged.contains("# dxgi.maxFrameLatency = 0"))
        XCTAssertTrue(merged.contains("# other comment"))
    }

    func testRemoveRestoresOriginalSnapshot() throws {
        let original = "# user authored conf\ndxgi.syncInterval = -1\n"
        try original.write(to: confURL, atomically: true, encoding: .utf8)
        DXVKGameConf.apply(
            posture: .init(maxFrameLatency: 1, maxDeviceMemoryMegabytes: 8_192),
            executable: exeURL
        )
        DXVKGameConf.remove(executable: exeURL)
        let restored = try String(contentsOf: confURL, encoding: .utf8)
        XCTAssertEqual(restored, original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: confURL.appendingPathExtension("macbottle.orig").path(percentEncoded: false)
        ))
    }
}
