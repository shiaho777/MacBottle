//
//  FrameThroughputObserverTests.swift
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

final class FrameThroughputObserverTests: XCTestCase {
    func testLongHealthySessionIsEvidence() {
        let verdict = FrameThroughputObserver.record(
            runID: UUID(),
            programKey: "game",
            sessionSeconds: 600,
            exitCode: 0,
            posture: .skyline
        )
        XCTAssertNotNil(verdict)
        XCTAssertTrue(verdict?.engaged == true)
    }

    func testQuickCrashIsNotEvidence() {
        XCTAssertNil(FrameThroughputObserver.record(
            runID: UUID(),
            programKey: "game",
            sessionSeconds: 12,
            exitCode: 1,
            posture: .skyline
        ))
    }

    func testShortButCleanSessionIsNotEvidence() {
        XCTAssertNil(FrameThroughputObserver.record(
            runID: UUID(),
            programKey: "game",
            sessionSeconds: 20,
            exitCode: 0,
            posture: .balanced
        ))
    }

    func testTunerNeverOverridesUserChoice() {
        let userChoice = GameBoostProfile(posture: .efficient, autoTuned: false)
        let verdict = FrameThroughputObserver.Verdict(
            runID: UUID(),
            programKey: "game",
            sessionSeconds: 3000,
            engaged: true,
            posture: .efficient
        )
        let proposal = FrameThroughputObserver.proposePosture(current: userChoice, verdict: verdict)
        XCTAssertEqual(proposal, userChoice)
    }
}
