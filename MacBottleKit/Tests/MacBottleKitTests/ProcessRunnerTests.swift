//
//  ProcessRunnerTests.swift
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

final class ProcessRunnerTests: XCTestCase {
    func testLargeOutputDoesNotDeadlock() async throws {
        // ~108 KB, comfortably past the kernel pipe buffer. The old
        // implementation read only after termination and would hang here.
        let result = try await ProcessRunner.run(
            path: "/bin/sh",
            arguments: ["-c", "seq 1 20000"]
        )
        XCTAssertTrue(result.isSuccess)
        XCTAssertGreaterThan(result.standardOutput.count, 64 * 1024)
        XCTAssertTrue(result.standardOutputString.contains("20000"))
    }

    func testCapturesStderrSeparately() async throws {
        let result = try await ProcessRunner.run(
            path: "/bin/sh",
            arguments: ["-c", "echo out; echo err >&2; exit 7"]
        )
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.standardOutputString.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertEqual(result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines), "err")
    }
}
