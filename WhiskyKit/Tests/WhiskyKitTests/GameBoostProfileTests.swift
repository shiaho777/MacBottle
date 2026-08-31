//
//  GameBoostProfileTests.swift
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

final class GameBoostProfileTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GameBoostRegistry.resetForTests()
    }

    override func tearDown() {
        GameBoostRegistry.resetForTests()
        super.tearDown()
    }

    func testSkylineOverlayRemovesKnownLatencyCosts() {
        let overlay = GameBoostProfile(posture: .skyline).environmentOverlay()
        XCTAssertEqual(overlay["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"], "0")
        XCTAssertEqual(overlay["MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS"], "1")
        XCTAssertEqual(overlay["MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION"], "1")
        XCTAssertEqual(overlay["MVK_CONFIG_FORCE_LOW_POWER_GPU"], "0")
        XCTAssertEqual(overlay["D3DM_MULTITHREADED_INTERFACE_ENABLE"], "1")
    }

    func testEfficientPosturePrefersLowPowerGPU() {
        let overlay = GameBoostProfile(posture: .efficient).environmentOverlay()
        XCTAssertEqual(overlay["MVK_CONFIG_FORCE_LOW_POWER_GPU"], "1")
    }

    func testBalancedPostureAddsNoGPUPinning() {
        let overlay = GameBoostProfile(posture: .balanced).environmentOverlay()
        XCTAssertNil(overlay["MVK_CONFIG_FORCE_LOW_POWER_GPU"])
        XCTAssertEqual(overlay["MVK_CONFIG_DEBUG"], "0")
    }

    func testProfilePersistsAcrossRegistryReload() {
        GameBoostRegistry.setProfile(
            GameBoostProfile(posture: .skyline, autoTuned: true),
            for: "game-1"
        )
        // New read path must observe the persisted value (cache is
        // process-wide by design; the reset in tearDown simulates the
        // next app run for the store file itself).
        XCTAssertEqual(GameBoostRegistry.profile(for: "game-1")?.posture, .skyline)
        XCTAssertTrue(GameBoostRegistry.profile(for: "game-1")?.autoTuned == true)
    }

    func testClearingProfileRemovesIt() {
        GameBoostRegistry.setProfile(GameBoostProfile(posture: .efficient), for: "game-2")
        GameBoostRegistry.setProfile(nil, for: "game-2")
        XCTAssertNil(GameBoostRegistry.profile(for: "game-2"))
    }
}
