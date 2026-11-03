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
@testable import MacBottleKit

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

        let engineID = "crossover-3.0.0"
        XCTAssertFalse(coordinator.isWarm(bottle: bottle, engineID: engineID))
        coordinator.beginWarmup(bottle: bottle, engineID: engineID)
        XCTAssertTrue(coordinator.isWarming(bottle: bottle, engineID: engineID))
        coordinator.finishWarmup(bottle: bottle, engineID: engineID, success: true)
        XCTAssertTrue(coordinator.isWarm(bottle: bottle, engineID: engineID))
        XCTAssertFalse(coordinator.isWarming(bottle: bottle, engineID: engineID))

        XCTAssertFalse(coordinator.isDXVKReady(bottle: bottle, engineID: engineID))
        coordinator.markDXVKReady(bottle: bottle, engineID: engineID)
        XCTAssertTrue(coordinator.isDXVKReady(bottle: bottle, engineID: engineID))

        // Force-stopping a bottle clears warm state but not the DXVK
        // DLLs that are still installed in the prefix.
        coordinator.clearWarm(bottle: bottle)
        XCTAssertFalse(coordinator.isWarm(bottle: bottle, engineID: engineID))
        XCTAssertTrue(coordinator.isDXVKReady(bottle: bottle, engineID: engineID))

        // A different engine build must not inherit the previous
        // engine's warm or DXVK state.
        XCTAssertFalse(coordinator.isWarm(bottle: bottle, engineID: "crossover-4.0.0"))
        XCTAssertFalse(coordinator.isDXVKReady(bottle: bottle, engineID: "crossover-4.0.0"))

        coordinator.invalidateEngineBoundState()
        XCTAssertFalse(coordinator.isWarm(bottle: bottle, engineID: engineID))
        XCTAssertFalse(coordinator.isDXVKReady(bottle: bottle, engineID: engineID))
        coordinator.dismiss()
    }

    func testInvalidateBottleLeavesOtherBottlesWarm() {
        let coordinator = ProgramLaunchCoordinator.shared
        coordinator.dismiss()
        let bottleA = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/macbottle-a-\(UUID().uuidString)"),
            inFlight: true
        )
        let bottleB = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/macbottle-b-\(UUID().uuidString)"),
            inFlight: true
        )
        coordinator.markWarm(bottle: bottleA, engineID: "e1")
        coordinator.markWarm(bottle: bottleB, engineID: "e1")
        coordinator.invalidate(bottle: bottleA)
        XCTAssertFalse(coordinator.isWarm(bottle: bottleA, engineID: "e1"))
        XCTAssertTrue(coordinator.isWarm(bottle: bottleB, engineID: "e1"))
        coordinator.dismiss()
    }

    func testProvisioningPhaseRoundTrip() {
        let coordinator = ProgramLaunchCoordinator.shared
        coordinator.dismiss()
        let bottle = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/macbottle-prov-\(UUID().uuidString)"),
            inFlight: true
        )
        bottle.settings.name = "Prov"
        let programURL = URL(fileURLWithPath: "/tmp/game.exe")
        XCTAssertTrue(coordinator.beginLaunch(
            programURL: programURL,
            programName: "game.exe",
            bottle: bottle
        ))
        coordinator.beginProvisioning(
            programName: "game.exe",
            bottleName: "Prov",
            detail: "winetricks vcrun2022"
        )
        XCTAssertEqual(
            coordinator.phase,
            .provisioning(programName: "game.exe", detail: "winetricks vcrun2022")
        )
        coordinator.updateProvisioning(detail: "registry HKCU")
        XCTAssertEqual(
            coordinator.phase,
            .provisioning(programName: "game.exe", detail: "registry HKCU")
        )
        coordinator.endProvisioning(programName: "game.exe", bottleName: "Prov")
        XCTAssertEqual(
            coordinator.phase,
            .launching(programName: "game.exe", bottleName: "Prov")
        )
        coordinator.dismiss()
    }

    func testCompleteLaunchDoesNotOverwriteSilentFailure() {
        let coordinator = ProgramLaunchCoordinator.shared
        coordinator.dismiss()
        let bottle = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/macbottle-complete-\(UUID().uuidString)"),
            inFlight: true
        )
        let programURL = URL(fileURLWithPath: "/tmp/game.exe")
        XCTAssertTrue(coordinator.beginLaunch(
            programURL: programURL,
            programName: "game.exe",
            bottle: bottle
        ))
        coordinator.finishLaunchFailure(
            programURL: programURL,
            programName: "game.exe",
            message: "silent exit"
        )
        coordinator.completeLaunch(
            programURL: programURL,
            programName: "game.exe",
            exitCode: 0
        )
        XCTAssertEqual(
            coordinator.phase,
            .failed(programName: "game.exe", message: "silent exit")
        )
        coordinator.dismiss()
    }

    func testCompleteLaunchReportsNonZeroExit() {
        let coordinator = ProgramLaunchCoordinator.shared
        coordinator.dismiss()
        let bottle = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/macbottle-exit-\(UUID().uuidString)"),
            inFlight: true
        )
        let programURL = URL(fileURLWithPath: "/tmp/game.exe")
        XCTAssertTrue(coordinator.beginLaunch(
            programURL: programURL,
            programName: "game.exe",
            bottle: bottle
        ))
        coordinator.completeLaunch(
            programURL: programURL,
            programName: "game.exe",
            exitCode: 7
        )
        if case .failed(let name, let message) = coordinator.phase {
            XCTAssertEqual(name, "game.exe")
            XCTAssertTrue(message.contains("7"))
        } else {
            XCTFail("expected failed phase")
        }
        coordinator.dismiss()
    }

    func testSilentExitMessageFlagsQuickEmptyExit() {
        let message = ProgramLaunchCoordinator.silentExitFailureMessage(
            secondsToExit: 4,
            processOutputByteCount: 0
        )
        XCTAssertNotNil(message)
    }

    func testSilentExitMessageIgnoresOutputAndSlowExits() {
        XCTAssertNil(ProgramLaunchCoordinator.silentExitFailureMessage(
            secondsToExit: 4,
            processOutputByteCount: 128
        ))
        XCTAssertNil(ProgramLaunchCoordinator.silentExitFailureMessage(
            secondsToExit: 30,
            processOutputByteCount: 0
        ))
        XCTAssertNil(ProgramLaunchCoordinator.silentExitFailureMessage(
            secondsToExit: -1,
            processOutputByteCount: 0
        ))
    }
}
