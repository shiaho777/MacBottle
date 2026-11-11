//
//  FrameTimeParserTests.swift
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

final class FrameTimeParserTests: XCTestCase {
    func testParsesFPSLinesIntoMilliseconds() {
        let samples = FrameTimeParser.parse("FPS: 60\nfps=30\n")
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0], 1_000.0 / 60.0, accuracy: 0.001)
        XCTAssertEqual(samples[1], 1_000.0 / 30.0, accuracy: 0.001)
    }

    func testPrefersExplicitFrameTimeOverFPSOnSameLine() {
        let samples = FrameTimeParser.parse("frametime 12.5 ms (FPS: 80)")
        XCTAssertEqual(samples, [12.5])
    }

    func testParsesBareMilliseconds() {
        XCTAssertEqual(FrameTimeParser.parse("frame 8.0 ms"), [8.0])
    }

    func testIgnoresImplausibleValues() {
        XCTAssertTrue(FrameTimeParser.parse("FPS: 0\nframetime 5000 ms\n").isEmpty)
    }

    func testStatsP50P95AndOnePercentLow() {
        let stats = FrameTimeParser.stats([10, 20, 30, 40, 50])
        XCTAssertEqual(stats?.sampleCount, 5)
        XCTAssertEqual(stats?.averageMilliseconds ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(stats?.p50Milliseconds, 30)
        XCTAssertEqual(stats?.p95Milliseconds, 50)
        XCTAssertEqual(stats?.onePercentLowFPS ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(stats?.averageFPS ?? 0, 1_000.0 / 30.0, accuracy: 0.001)
    }

    func testEmptyStats() {
        XCTAssertNil(FrameTimeParser.stats([]))
    }
}
