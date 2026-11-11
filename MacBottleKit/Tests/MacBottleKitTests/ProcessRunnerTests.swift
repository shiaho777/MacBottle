//
//  ProcessRunnerTests.swift
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

    func testAsyncTimeoutKillsTheChild() async {
        let started = Date()
        do {
            _ = try await ProcessRunner.run(
                path: "/bin/sh",
                arguments: ["-c", "sleep 30"],
                timeout: .milliseconds(200)
            )
            XCTFail("expected a timeout")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut(seconds: 0.2))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "timeout must not wait for the child")
    }

    func testSyncRunCapturesOutput() throws {
        let result = try ProcessRunner.runSync(
            path: "/bin/sh",
            arguments: ["-c", "echo sync-out; exit 3"],
            timeout: .seconds(10)
        )
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.standardOutputString.trimmingCharacters(in: .whitespacesAndNewlines), "sync-out")
    }

    func testSyncTimeoutKillsTheChild() {
        do {
            _ = try ProcessRunner.runSync(
                path: "/bin/sh",
                arguments: ["-c", "sleep 30"],
                timeout: .milliseconds(200)
            )
            XCTFail("expected a timeout")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut(seconds: 0.2))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLaunchReturnsRunningProcess() throws {
        let process = try ProcessRunner.launch(
            path: "/bin/sh",
            arguments: ["-c", "sleep 5"]
        )
        XCTAssertTrue(process.isRunning)
        ProcessRunner.terminate(process)
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
    }
}
