//
//  RuntimeLaunchOptimizerTests.swift
//  WhiskyKitTests
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

final class RuntimeLaunchOptimizerTests: XCTestCase {
    func testInstallerNameDetected() {
        let url = URL(fileURLWithPath: "/tmp/GameSetup.exe")
        XCTAssertEqual(RuntimeLaunchOptimizer.profile(forExecutableAt: url), .installer)
    }

    func testUninstNameDetected() {
        let url = URL(fileURLWithPath: "/tmp/uninst.exe")
        XCTAssertEqual(RuntimeLaunchOptimizer.profile(forExecutableAt: url), .installer)
    }

    func testClassic32DisablesAVXAndWriteWatch() {
        let env = RuntimeLaunchOptimizer.environment(
            profile: .classic32,
            bottleDXVKEnabled: true,
            base: [
                "WINEPREFIX": "/tmp/bottle",
                "WINEDEBUG": "fixme-all",
                "GST_DEBUG": "1",
                "ROSETTA_ADVERTISE_AVX": "1",
                "DXVK_ASYNC": "1",
                "DXVK_LOG_LEVEL": "info",
                "DXVK_STATE_CACHE": "1"
            ]
        )
        XCTAssertEqual(env["WINEDEBUG"], "-all")
        XCTAssertEqual(env["GST_DEBUG"], "0")
        XCTAssertNil(env["ROSETTA_ADVERTISE_AVX"])
        XCTAssertEqual(env["WINE_DISABLE_KERNEL_WRITEWATCH"], "1")
        XCTAssertNil(env["DXVK_ASYNC"])
        XCTAssertNil(env["DXVK_LOG_LEVEL"])
        XCTAssertNil(env["DXVK_STATE_CACHE"])
        XCTAssertFalse(RuntimeLaunchOptimizer.effectiveDXVKEnabled(
            profile: .classic32,
            bottleDXVKEnabled: true
        ))
        XCTAssertTrue(env["WINEDLLOVERRIDES"]?.contains("winemenubuilder.exe=d") == true)
        XCTAssertTrue(env["WINEDLLOVERRIDES"]?.contains("d3d9") == true)
        XCTAssertTrue(env["WINEDLLOVERRIDES"]?.contains("=b") == true)
        XCTAssertTrue(env["WINEDLLOVERRIDES"]?.contains("d3d12=d") == true)
        XCTAssertTrue(env["MVK_CONFIG_FAST_MATH_ENABLED"] == "1")
    }

    func testModern64KeepsUserDXVKSettings() {
        let env = RuntimeLaunchOptimizer.environment(
            profile: .modern64,
            bottleDXVKEnabled: true,
            base: [
                "WINEPREFIX": "/tmp/bottle",
                "DXVK_HUD": "fps"
            ]
        )
        XCTAssertEqual(env["DXVK_HUD"], "fps")
        XCTAssertEqual(env["DXVK_LOG_LEVEL"], "none")
        XCTAssertEqual(env["DXVK_STATE_CACHE"], "1")
    }

    func testStartArgumentsHighPriorityForModernGames() {
        let url = URL(fileURLWithPath: "/tmp/game.exe")
        let args = RuntimeLaunchOptimizer.startArguments(
            profile: .modern64,
            executable: url,
            extraArgs: ["-windowed"]
        )
        XCTAssertEqual(Array(args.prefix(4)), ["start", "/wait", "/high", "/unix"])
        XCTAssertEqual(args.last, "-windowed")
    }

    func testStartArgumentsNoHighForClassic32() {
        let url = URL(fileURLWithPath: "/tmp/classic.exe")
        let args = RuntimeLaunchOptimizer.startArguments(
            profile: .classic32,
            executable: url,
            extraArgs: []
        )
        XCTAssertEqual(Array(args.prefix(3)), ["start", "/wait", "/unix"])
        XCTAssertFalse(args.contains("/high"))
    }

    func testStartArgumentsNoHighForInstaller() {
        let url = URL(fileURLWithPath: "/tmp/setup.exe")
        let args = RuntimeLaunchOptimizer.startArguments(
            profile: .installer,
            executable: url,
            extraArgs: []
        )
        XCTAssertFalse(args.contains("/high"))
    }

    func testUserEnvironmentWinsOverOptimizer() {
        let base = RuntimeLaunchOptimizer.environment(
            profile: .classic32,
            bottleDXVKEnabled: false,
            base: ["WINEPREFIX": "/tmp"]
        )
        var merged = base
        merged.merge(["WINEDEBUG": "err+all"], uniquingKeysWith: { $1 })
        XCTAssertEqual(merged["WINEDEBUG"], "err+all")
    }
}
