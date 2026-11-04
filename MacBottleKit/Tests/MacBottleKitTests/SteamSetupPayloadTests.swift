//
//  SteamSetupPayloadTests.swift
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

final class SteamSetupPayloadTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "steam-setup-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeFile(named name: String, bytes: Int, magic: [UInt8]) throws -> URL {
        var data = Data(magic)
        if bytes > magic.count {
            data.append(Data(repeating: 0, count: bytes - magic.count))
        }
        let url = workDir.appending(path: name)
        try data.write(to: url)
        return url
    }

    func testAcceptsLargeMZPayload() throws {
        let url = try makeFile(named: "setup.exe", bytes: SteamSetupPayload.minimumBytes + 1, magic: [0x4D, 0x5A])
        XCTAssertNoThrow(try SteamSetupPayload.validate(at: url))
    }

    func testRejectsNonExecutableMagic() throws {
        let url = try makeFile(named: "page.html", bytes: SteamSetupPayload.minimumBytes + 1, magic: [0x3C, 0x21])
        XCTAssertThrowsError(try SteamSetupPayload.validate(at: url)) { error in
            XCTAssertEqual(error as? SteamSetupError, .notAnExecutable)
        }
    }

    func testRejectsTruncatedDownload() throws {
        let url = try makeFile(named: "short.exe", bytes: 1024, magic: [0x4D, 0x5A])
        XCTAssertThrowsError(try SteamSetupPayload.validate(at: url)) { error in
            guard case .tooSmall(let bytes, let minimum)? = error as? SteamSetupError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(bytes, 1024)
            XCTAssertEqual(minimum, SteamSetupPayload.minimumBytes)
        }
    }
}
