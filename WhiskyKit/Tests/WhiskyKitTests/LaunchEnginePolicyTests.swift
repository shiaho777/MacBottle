//
//  LaunchEnginePolicyTests.swift
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

final class LaunchEnginePolicyTests: XCTestCase {
    func testRecipeD3DMetalPrefersD3DMetalEngineWhenInstalled() {
        let recipe = Recipe(
            id: "test.cp",
            title: "Test",
            dxVersion: .d3d12,
            minMacOS: "14.0",
            renderer: .d3dmetal,
            compatibility: .silver
        )
        let exe = URL(fileURLWithPath: "/tmp/fake-game.exe")
        let decision = LaunchEnginePolicy.decide(
            executable: exe,
            recipe: recipe,
            bottleDXVKEnabled: false
        )
        if WineEngineCatalog.d3dMetalEngine().isInstalled() {
            XCTAssertEqual(decision.engineID, WineEngineCatalog.d3dMetalIdentifier)
        } else {
            XCTAssertEqual(decision.engineID, WineEngineCatalog.modernIdentifier)
        }
        XCTAssertFalse(decision.bottlePinned)
    }

    func testRecipeDXVKUsesModern() {
        let recipe = Recipe(
            id: "test.dxvk",
            title: "Test",
            dxVersion: .d3d11,
            minMacOS: "14.0",
            renderer: .dxvk,
            compatibility: .gold
        )
        let decision = LaunchEnginePolicy.decide(
            executable: URL(fileURLWithPath: "/tmp/game.exe"),
            recipe: recipe,
            bottleDXVKEnabled: true
        )
        XCTAssertEqual(decision.engineID, WineEngineCatalog.modernIdentifier)
        XCTAssertFalse(decision.bottlePinned)
    }

    func testBottleEnginePinOverridesRecipe() {
        let recipe = Recipe(
            id: "test.cp",
            title: "Test",
            dxVersion: .d3d12,
            minMacOS: "14.0",
            renderer: .d3dmetal,
            compatibility: .silver
        )
        let decision = LaunchEnginePolicy.decide(
            executable: URL(fileURLWithPath: "/tmp/game.exe"),
            recipe: recipe,
            bottleDXVKEnabled: false,
            bottleEngineID: WineEngineCatalog.modernIdentifier
        )
        XCTAssertEqual(decision.engineID, WineEngineCatalog.modernIdentifier)
        XCTAssertTrue(decision.bottlePinned)
        XCTAssertTrue(decision.reason.contains("bottle.engine"))
    }

    func testBottleAutoTokenFallsThrough() {
        let decision = LaunchEnginePolicy.decide(
            executable: URL(fileURLWithPath: "/tmp/game.exe"),
            recipe: Recipe(
                id: "test.wined3d",
                title: "Test",
                dxVersion: .d3d9,
                minMacOS: "14.0",
                renderer: .wined3d,
                compatibility: .platinum
            ),
            bottleDXVKEnabled: false,
            bottleEngineID: LaunchEnginePolicy.autoEngineToken
        )
        XCTAssertEqual(decision.engineID, WineEngineCatalog.modernIdentifier)
        XCTAssertFalse(decision.bottlePinned)
    }

    func testScanKnownSystemBinaryDoesNotCrash() {
        let candidates = [
            URL(fileURLWithPath: "/Users/shiaho/Library/Application Support/"
                + "app.macbottle.MacBottle/Libraries/Wine/lib/wine/x86_64-windows/notepad.exe"),
            URL(fileURLWithPath: "/Users/shiaho/Library/Containers/app.macbottle.MacBottle/"
                + "Bottles/E16A4BB5-C875-41B6-94C4-86C6D9A08D24/drive_c/"
                + "Program Files (x86)/pvzHE/pvzHE-Launcher.exe")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let profile = PEImportScanner.scan(url: url)
            XCTAssertNotNil(profile)
            if url.lastPathComponent.contains("pvz") {
                XCTAssertEqual(profile?.architecture, .x32)
            }
            XCTAssertNotNil(profile?.delayLoadedDLLs)
            XCTAssertNotNil(profile?.origins)
        }
    }

    func testClassic32DecisionUsesModern() {
        let url = URL(fileURLWithPath: "/Users/shiaho/Library/Containers/app.macbottle.MacBottle/"
            + "Bottles/E16A4BB5-C875-41B6-94C4-86C6D9A08D24/drive_c/"
            + "Program Files (x86)/pvzHE/pvzHE-Launcher.exe")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let decision = LaunchEnginePolicy.decide(
            executable: url,
            recipe: nil,
            bottleDXVKEnabled: false
        )
        XCTAssertEqual(decision.engineID, WineEngineCatalog.modernIdentifier)
    }

    func testNormalizedBottleEngineID() {
        XCTAssertNil(LaunchEnginePolicy.normalizedBottleEngineID(nil))
        XCTAssertNil(LaunchEnginePolicy.normalizedBottleEngineID("auto"))
        XCTAssertNil(LaunchEnginePolicy.normalizedBottleEngineID("  "))
        XCTAssertEqual(
            LaunchEnginePolicy.normalizedBottleEngineID("crossover"),
            WineEngineCatalog.modernIdentifier
        )
    }
}
