//
//  RecipeProvisionerTests.swift
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
final class RecipeProvisionerTests: XCTestCase {
    private var workDir: URL!
    private var store: RecipeProvisioningStore!
    private var bottle: Bottle!

    override func setUp() async throws {
        try await super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(component: "provisioner-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        store = RecipeProvisioningStore(root: workDir.appending(path: "state"))
        let bottleURL = workDir.appending(path: "bottle")
        try? FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workDir)
        try await super.tearDown()
    }

    private func makeRecipe(
        id: String = "steam.1",
        verbs: [String] = ["vcrun2022", "dotnet48"],
        registry: [RegistryEntry] = [
            RegistryEntry(
                path: #"HKEY_CURRENT_USER\Software\Test"#,
                key: "Enabled",
                type: .dword,
                value: "1"
            )
        ]
    ) -> Recipe {
        Recipe(
            id: id,
            title: "Test Game",
            dxVersion: .d3d11,
            minMacOS: "14.0",
            renderer: .dxvk,
            winetricks: verbs,
            registry: registry,
            compatibility: .gold
        )
    }

    func testProvisioningRunsEveryStepOnce() async throws {
        let calls = CallLog()
        let provisioner = RecipeProvisioner(
            store: store,
            runVerb: { verb, _ in await calls.append("verb:\(verb)") },
            runRegistry: { entry, _ in await calls.append("reg:\(entry.key)") }
        )
        let recipe = makeRecipe()

        let first = try await provisioner.provisionIfNeeded(recipe: recipe, bottle: bottle)
        XCTAssertTrue(first)
        let firstCalls = await calls.snapshot()
        XCTAssertEqual(firstCalls, ["verb:vcrun2022", "verb:dotnet48", "reg:Enabled"])

        let second = try await provisioner.provisionIfNeeded(recipe: recipe, bottle: bottle)
        XCTAssertFalse(second, "a complete receipt must short-circuit the second run")
        let secondCalls = await calls.snapshot()
        XCTAssertEqual(secondCalls, firstCalls)
    }

    func testFailedVerbResumesFromLastCompletedStep() async throws {
        let calls = CallLog()
        let provisioner = RecipeProvisioner(
            store: store,
            runVerb: { verb, _ in
                await calls.append("verb:\(verb)")
                if verb == "dotnet48" {
                    throw RecipeProvisioningError.verbFailed(verb: verb, output: "boom")
                }
            },
            runRegistry: { entry, _ in await calls.append("reg:\(entry.key)") }
        )
        let recipe = makeRecipe()

        do {
            _ = try await provisioner.provisionIfNeeded(recipe: recipe, bottle: bottle)
            XCTFail("expected the failing verb to throw")
        } catch {
            // expected
        }
        let firstAttempt = await calls.snapshot()
        XCTAssertEqual(firstAttempt, ["verb:vcrun2022", "verb:dotnet48"])

        // A second attempt must skip vcrun2022 and retry dotnet48.
        do {
            _ = try await provisioner.provisionIfNeeded(recipe: recipe, bottle: bottle)
            XCTFail("expected the failing verb to throw again")
        } catch {
            // expected
        }
        let secondAttempt = await calls.snapshot()
        XCTAssertEqual(
            secondAttempt,
            ["verb:vcrun2022", "verb:dotnet48", "verb:dotnet48"]
        )
    }

    func testFingerprintChangeReRunsTheWholePlan() async throws {
        let calls = CallLog()
        let provisioner = RecipeProvisioner(
            store: store,
            runVerb: { verb, _ in await calls.append("verb:\(verb)") },
            runRegistry: { entry, _ in await calls.append("reg:\(entry.key)") }
        )

        _ = try await provisioner.provisionIfNeeded(
            recipe: makeRecipe(verbs: ["vcrun2022"]),
            bottle: bottle
        )
        _ = try await provisioner.provisionIfNeeded(
            recipe: makeRecipe(verbs: ["vcrun2022", "corefonts"]),
            bottle: bottle
        )

        let finalCalls = await calls.snapshot()
        XCTAssertEqual(
            finalCalls,
            ["verb:vcrun2022", "reg:Enabled", "verb:vcrun2022", "verb:corefonts", "reg:Enabled"]
        )
    }

    func testTwoRecipesInSameBottleKeepIndependentReceipts() async throws {
        let calls = CallLog()
        let provisioner = RecipeProvisioner(
            store: store,
            runVerb: { verb, _ in await calls.append("verb:\(verb)") },
            runRegistry: { entry, _ in await calls.append("reg:\(entry.key)") }
        )
        let recipeA = makeRecipe(id: "steam.a", verbs: ["vcrun2022"], registry: [])
        let recipeB = makeRecipe(id: "steam.b", verbs: ["corefonts"], registry: [])

        _ = try await provisioner.provisionIfNeeded(recipe: recipeA, bottle: bottle)
        _ = try await provisioner.provisionIfNeeded(recipe: recipeB, bottle: bottle)
        let firstPass = await calls.snapshot()
        XCTAssertEqual(firstPass, ["verb:vcrun2022", "verb:corefonts"])

        _ = try await provisioner.provisionIfNeeded(recipe: recipeA, bottle: bottle)
        _ = try await provisioner.provisionIfNeeded(recipe: recipeB, bottle: bottle)
        let secondPass = await calls.snapshot()
        XCTAssertEqual(secondPass, firstPass, "one recipe's receipt must not erase another's")
    }

    func testEmptyPlanDoesNothing() async throws {
        let calls = CallLog()
        let provisioner = RecipeProvisioner(
            store: store,
            runVerb: { verb, _ in await calls.append("verb:\(verb)") },
            runRegistry: { entry, _ in await calls.append("reg:\(entry.key)") }
        )
        let recipe = makeRecipe(verbs: [], registry: [])

        let didWork = try await provisioner.provisionIfNeeded(recipe: recipe, bottle: bottle)
        XCTAssertFalse(didWork)
        let invoked = await calls.snapshot()
        XCTAssertTrue(invoked.isEmpty)
        XCTAssertTrue(store.records(bottleKey: ProgramRunLogStore.bottleKey(for: bottle)).isEmpty)
    }
}

private actor CallLog {
    private var calls: [String] = []

    func append(_ call: String) {
        calls.append(call)
    }

    func snapshot() -> [String] {
        calls
    }
}
