//
//  ProcessRunStreamTests.swift
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

final class ProcessRunStreamTests: XCTestCase {
    private func makeLogFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(component: "macbottle-runstream-\(UUID().uuidString).log")
        try Data().write(to: url)
        return url
    }

    func testQuietRunWithFileHandleCapturesOutputToLog() async throws {
        let logURL = try makeLogFile()
        defer { try? FileManager.default.removeItem(at: logURL) }
        let handle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["pvzhe-capture-ok"]

        let stream = try process.runStream(
            name: "echo",
            fileHandle: handle,
            quiet: true,
            systemLog: false
        )
        for await _ in stream {}

        let data = try Data(contentsOf: logURL)
        let content = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(content.contains("pvzhe-capture-ok"), "run log was missing process output: \(content)")
    }

    func testQuietRunWithoutFileHandleStaysSilent() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["quiet-discarded"]

        let stream = try process.runStream(
            name: "echo",
            fileHandle: nil,
            quiet: true,
            systemLog: false
        )
        for await _ in stream {}
    }
}
