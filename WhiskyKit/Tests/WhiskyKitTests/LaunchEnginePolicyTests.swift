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

    func testScanGeneratedPEFixturesDoNotCrash() throws {
        let workRoot = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-pe-fixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workRoot) }

        let pe32 = workRoot.appending(path: "classic32.exe")
        try Self.writePEFixture(optionalHeaderMagic: 0x010B, to: pe32)
        let scan32 = PEImportScanner.scan(url: pe32)
        XCTAssertEqual(scan32?.architecture, .x32)

        let pe64 = workRoot.appending(path: "modern64.exe")
        try Self.writePEFixture(optionalHeaderMagic: 0x020B, to: pe64)
        XCTAssertEqual(PEImportScanner.scan(url: pe64)?.architecture, .x64)

        let garbage = workRoot.appending(path: "garbage.exe")
        try Data("this is not a PE file".utf8).write(to: garbage)
        XCTAssertNil(PEImportScanner.scan(url: garbage))
    }

    func testClassic32DecisionUsesModern() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-classic32-\(UUID().uuidString).exe")
        try Self.writePEFixture(optionalHeaderMagic: 0x010B, to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let decision = LaunchEnginePolicy.decide(
            executable: fixture,
            recipe: nil,
            bottleDXVKEnabled: false
        )
        XCTAssertEqual(decision.engineID, WineEngineCatalog.modernIdentifier)
    }

    /// Builds a minimal PE image: DOS header with e_lfanew, PE
    /// signature, an empty COFF header, and an optional header carrying
    /// just the magic that decides 32- vs 64-bit classification.
    private static func writePEFixture(optionalHeaderMagic: UInt16, to url: URL) throws {
        var data = Data(repeating: 0, count: 0x44 + 24 + 240)

        let dosBytes: [UInt8] = [0x4D, 0x5A] // "MZ"
        data.replaceSubrange(0..<2, with: dosBytes)
        let peOffset = UInt32(0x40)
        withUnsafeBytes(of: peOffset.littleEndian) { data.replaceSubrange(0x3C..<0x40, with: $0) }
        data.replaceSubrange(0x40..<0x44, with: [0x50, 0x45, 0x00, 0x00]) // "PE\0\0"

        let coffOffset = 0x44 // PE signature + 4
        let machine: UInt16 = optionalHeaderMagic == 0x010B ? 0x014C : 0x8664
        withUnsafeBytes(of: machine.littleEndian) {
            data.replaceSubrange(coffOffset..<(coffOffset + 2), with: $0)
        }
        withUnsafeBytes(of: UInt16(0xE0).littleEndian) {
            data.replaceSubrange((coffOffset + 16)..<(coffOffset + 18), with: $0)
        }
        withUnsafeBytes(of: UInt16(0x0002).littleEndian) {
            data.replaceSubrange((coffOffset + 18)..<(coffOffset + 20), with: $0)
        }

        let optionalOffset = coffOffset + 20
        withUnsafeBytes(of: optionalHeaderMagic.littleEndian) {
            data.replaceSubrange(optionalOffset..<(optionalOffset + 2), with: $0)
        }

        try data.write(to: url)
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

    func testDecisionRewriteReportsActualEngine() {
        let original = LaunchEnginePolicy.Decision(
            engineID: WineEngineCatalog.d3dMetalIdentifier,
            reason: "pe.d3d12",
            importProfile: nil,
            recipeRenderer: nil,
            bottlePinned: false
        )

        let rewritten = LaunchEnginePolicy.decision(
            original,
            reportingActualEngineID: WineEngineCatalog.modernIdentifier
        )
        XCTAssertEqual(rewritten.engineID, WineEngineCatalog.modernIdentifier)
        XCTAssertTrue(rewritten.reason.contains(WineEngineCatalog.d3dMetalIdentifier))
        XCTAssertEqual(rewritten.importProfile, original.importProfile)
        XCTAssertEqual(rewritten.recipeRenderer, original.recipeRenderer)
        XCTAssertEqual(rewritten.bottlePinned, original.bottlePinned)
    }

    func testDecisionRewriteKeepsMatchingDecision() {
        let original = LaunchEnginePolicy.Decision(
            engineID: WineEngineCatalog.modernIdentifier,
            reason: "classic32",
            importProfile: nil,
            recipeRenderer: nil,
            bottlePinned: false
        )
        let rewritten = LaunchEnginePolicy.decision(
            original,
            reportingActualEngineID: WineEngineCatalog.modernIdentifier
        )
        XCTAssertEqual(rewritten, original)
    }
}
