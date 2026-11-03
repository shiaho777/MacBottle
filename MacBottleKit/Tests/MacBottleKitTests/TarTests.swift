//
//  TarTests.swift
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

final class TarTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(component: "tar-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    func testRoundTripExtractsFolderContents() throws {
        let source = workDir.appending(path: "payload")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source.appending(path: "hello.txt"))

        let archive = workDir.appending(path: "payload.tgz")
        try Tar.tar(folder: source, toURL: archive)

        let destination = workDir.appending(path: "out")
        try Tar.untar(tarBall: archive, toURL: destination)

        let extracted = destination.appending(path: "payload/hello.txt")
        XCTAssertEqual(try String(contentsOf: extracted, encoding: .utf8), "hello")
    }

    func testPathTraversalEntryIsRejected() async throws {
        let inside = workDir.appending(path: "inside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let outside = workDir.appending(path: "outside.txt")
        try Data("pwn".utf8).write(to: outside)
        let archive = workDir.appending(path: "evil.tgz")

        let result = try await ProcessRunner.run(
            path: "/usr/bin/tar",
            arguments: ["-czf", archive.path, "-C", inside.path, "../outside.txt"]
        )
        XCTAssertTrue(result.isSuccess)

        let destination = workDir.appending(path: "out")
        XCTAssertThrowsError(try Tar.untar(tarBall: archive, toURL: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appending(path: "../outside.txt").path))
    }

    func testSymlinkEscapeIsRejected() async throws {
        let source = workDir.appending(path: "link-src")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: source.appending(path: "escape"),
            withDestinationURL: URL(fileURLWithPath: "/tmp")
        )
        let archive = workDir.appending(path: "link.tgz")
        let result = try await ProcessRunner.run(
            path: "/usr/bin/tar",
            arguments: ["-czf", archive.path, "-C", source.path, "escape"]
        )
        XCTAssertTrue(result.isSuccess)

        let destination = workDir.appending(path: "out")
        XCTAssertThrowsError(try Tar.untar(tarBall: archive, toURL: destination))
    }
}
