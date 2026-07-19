//
//  ProgramLaunchCoordinatorTests.swift
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

@MainActor
final class ProgramLaunchCoordinatorTests: XCTestCase {
    func testBeginLaunchDebouncesDuplicateProgram() {
        let coordinator = ProgramLaunchCoordinator.shared
        coordinator.dismiss()

        let bottleURL = URL(fileURLWithPath: "/tmp/macbottle-test-bottle-\(UUID().uuidString)")
        let programURL = bottleURL.appending(path: "drive_c/game.exe")
        let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
        bottle.settings.name = "TestBottle"

        let first = coordinator.beginLaunch(
            programURL: programURL,
            programName: "game.exe",
            bottle: bottle
        )
        let second = coordinator.beginLaunch(
            programURL: programURL,
            programName: "game.exe",
            bottle: bottle
        )
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertTrue(coordinator.isLaunching(programURL: programURL))

        coordinator.finishLaunchSuccess(programURL: programURL, programName: "game.exe")
        XCTAssertFalse(coordinator.isLaunching(programURL: programURL))
        if case .launched(let name) = coordinator.phase {
            XCTAssertEqual(name, "game.exe")
        } else {
            XCTFail("expected launched phase")
        }
        coordinator.dismiss()
    }

    func testWarmupAndDXVKFlags() {
        let coordinator = ProgramLaunchCoordinator.shared
        coordinator.dismiss()
        let bottleURL = URL(fileURLWithPath: "/tmp/macbottle-warm-\(UUID().uuidString)")
        let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
        bottle.settings.name = "Warm"

        XCTAssertFalse(coordinator.isWarm(bottle: bottle))
        coordinator.beginWarmup(bottle: bottle)
        XCTAssertTrue(coordinator.isWarming(bottle: bottle))
        coordinator.finishWarmup(bottle: bottle, success: true)
        XCTAssertTrue(coordinator.isWarm(bottle: bottle))
        XCTAssertFalse(coordinator.isWarming(bottle: bottle))

        XCTAssertFalse(coordinator.isDXVKReady(bottle: bottle))
        coordinator.markDXVKReady(bottle: bottle)
        XCTAssertTrue(coordinator.isDXVKReady(bottle: bottle))
        coordinator.dismiss()
    }
}
