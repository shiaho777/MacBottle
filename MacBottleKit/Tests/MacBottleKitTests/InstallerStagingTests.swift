//
//  InstallerStagingTests.swift
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

final class InstallerStagingTests: XCTestCase {
    private var workDir: URL!
    private var bottleURL: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "installer-staging-\(UUID().uuidString)")
        bottleURL = workDir.appending(path: "bottle")
        try? FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeInstaller(named name: String) throws -> URL {
        let url = workDir.appending(path: name)
        try Data("installer".utf8).write(to: url)
        return url
    }

    func testCopiesOutsideInstallerIntoTheBottle() throws {
        let installer = try makeInstaller(named: "setup.exe")
        let staged = try InstallerStaging.stage(installer, inBottle: bottleURL)

        XCTAssertEqual(staged.lastPathComponent, "setup.exe")
        XCTAssertEqual(staged.deletingLastPathComponent().lastPathComponent, InstallerStaging.stagingFolderName)
        XCTAssertTrue(staged.path.hasPrefix(bottleURL.appending(path: "drive_c").path))
        XCTAssertEqual(try Data(contentsOf: staged), try Data(contentsOf: installer))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.path), "source must stay in place")
    }

    func testInstallerAlreadyInsideBottleIsReturnedUnchanged() throws {
        let inside = bottleURL.appending(path: "drive_c/Games/setup.exe")
        try FileManager.default.createDirectory(
            at: inside.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("installer".utf8).write(to: inside)

        let staged = try InstallerStaging.stage(inside, inBottle: bottleURL)
        XCTAssertEqual(staged, inside)
    }

    func testNonASCIIInstallerNameIsReplaced() throws {
        let installer = try makeInstaller(named: "安装程序.exe")
        let staged = try InstallerStaging.stage(installer, inBottle: bottleURL)

        let name = staged.lastPathComponent
        XCTAssertTrue(name.hasPrefix("installer_"))
        XCTAssertEqual(staged.pathExtension, "exe")
        XCTAssertTrue(name.unicodeScalars.allSatisfy(\.isASCII))
    }

    func testRestagingReplacesThePreviousCopy() throws {
        let installer = try makeInstaller(named: "setup.exe")
        let first = try InstallerStaging.stage(installer, inBottle: bottleURL)

        try Data("new-build".utf8).write(to: installer)
        let second = try InstallerStaging.stage(installer, inBottle: bottleURL)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: second), Data("new-build".utf8))
    }
}
