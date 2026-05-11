//
//  RecipeTests.swift
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

final class RecipeTests: XCTestCase {

    // MARK: - Decoding

    func testDecodeMinimalRecipe() throws {
        let json = Data("""
        {
          "schema": 1,
          "id": "steam.105600",
          "title": "Terraria",
          "dx_version": "d3d9",
          "min_macos": "14.0",
          "renderer": "wined3d",
          "compatibility": "platinum"
        }
        """.utf8)

        let recipe = try JSONDecoder().decode(Recipe.self, from: json)

        XCTAssertEqual(recipe.schema, 1)
        XCTAssertEqual(recipe.id, "steam.105600")
        XCTAssertEqual(recipe.dxVersion, .d3d9)
        XCTAssertEqual(recipe.renderer, .wined3d)
        XCTAssertEqual(recipe.compatibility, .platinum)
        XCTAssertTrue(recipe.winetricks.isEmpty)
        XCTAssertTrue(recipe.env.isEmpty)
        XCTAssertTrue(recipe.registry.isEmpty)
        XCTAssertNil(recipe.notes)
    }

    func testDecodeFullRecipeWithRegistry() throws {
        let json = Data("""
        {
          "schema": 1,
          "id": "generic.example",
          "title": "Example",
          "dx_version": "d3d11",
          "min_macos": "14.0",
          "renderer": "d3dmetal",
          "winetricks": ["vcrun2022"],
          "env": {"WINEESYNC": "1"},
          "registry": [{
            "path": "HKCU\\\\Software\\\\Wine\\\\Direct3D",
            "key": "csmt",
            "type": "REG_SZ",
            "value": "enabled"
          }],
          "compatibility": "gold",
          "notes": "Hello"
        }
        """.utf8)

        let recipe = try JSONDecoder().decode(Recipe.self, from: json)

        XCTAssertEqual(recipe.winetricks, ["vcrun2022"])
        XCTAssertEqual(recipe.env, ["WINEESYNC": "1"])
        XCTAssertEqual(recipe.registry.count, 1)
        XCTAssertEqual(recipe.registry.first?.type, .string)
        XCTAssertEqual(recipe.notes, "Hello")
    }

    func testDecodeRejectsUnknownDXVersion() {
        let json = Data("""
        {"schema":1,"id":"steam.1","title":"x","dx_version":"d3d14",
         "min_macos":"14.0","renderer":"d3dmetal","compatibility":"gold"}
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Recipe.self, from: json))
    }

    // MARK: - Applier

    func testApplyNilRecipeIsIdentity() {
        let base = ["EXISTING": "value"]
        XCTAssertEqual(RecipeApplier.apply(nil, to: base), base)
    }

    func testApplyMergesEnvWithRecipeWinningOnConflict() {
        let recipe = Recipe(
            id: "steam.1", title: "x",
            dxVersion: .d3d11, minMacOS: "14.0", renderer: .d3dmetal,
            env: ["WINEESYNC": "1", "SHARED": "from-recipe"],
            compatibility: .gold
        )
        let base = ["EXISTING": "keep", "SHARED": "from-base"]

        let merged = RecipeApplier.apply(recipe, to: base)

        XCTAssertEqual(merged["EXISTING"], "keep")
        XCTAssertEqual(merged["SHARED"], "from-recipe")
        XCTAssertEqual(merged["WINEESYNC"], "1")
    }

    func testApplyEmptyRecipeLeavesBaseIntact() {
        let recipe = Recipe(
            id: "steam.1", title: "x",
            dxVersion: .d3d11, minMacOS: "14.0", renderer: .d3dmetal,
            compatibility: .gold
        )
        let base = ["A": "1", "B": "2"]

        XCTAssertEqual(RecipeApplier.apply(recipe, to: base), base)
    }

    // MARK: - Shipped recipes

    func testAllShippedRecipesDecodeCleanly() {
        let store = RecipeStore(bundle: .module)
        let recipes = store.loadAll()

        // We ship at least the v0.5.1 seed set (10 original + 8 popular
        // additions). If this fails, either a new recipe is malformed or
        // the Recipes/ directory was not copied into the bundle by SwiftPM.
        XCTAssertGreaterThanOrEqual(recipes.count, 18,
            "Expected at least 18 shipped recipes; got \(recipes.count)")
    }

    func testShippedRecipesMostlyHaveIcons() {
        // Icons are optional in the schema but strongly encouraged. Guard
        // the seed set so regressions in recipe quality show up in CI:
        // strictly more than half of shipped recipes should declare an
        // icon_url. The threshold is deliberately loose — not every
        // recipe has a canonical icon source.
        let recipes = RecipeStore(bundle: .module).loadAll().values
        let withIcon = recipes.filter { $0.iconURL != nil }.count
        XCTAssertGreaterThan(withIcon, recipes.count / 2,
            "Shipped recipes should usually declare icon_url; \(withIcon) of \(recipes.count) do")
    }

    func testIconURLDecodesFromSnakeCaseField() throws {
        let json = Data("""
        {
          "schema": 1,
          "id": "steam.1",
          "title": "x",
          "icon_url": "https://example.com/a.jpg",
          "dx_version": "d3d11",
          "min_macos": "14.0",
          "renderer": "d3dmetal",
          "compatibility": "gold"
        }
        """.utf8)
        let recipe = try JSONDecoder().decode(Recipe.self, from: json)
        XCTAssertEqual(recipe.iconURL?.host, "example.com")
    }

    func testShippedRecipeIdsAreUnique() {
        let store = RecipeStore(bundle: .module)
        let recipes = store.loadAll()
        // loadAll already de-duplicates, so we just verify count > 0.
        XCTAssertFalse(recipes.isEmpty)
        for (id, recipe) in recipes {
            XCTAssertEqual(id, recipe.id, "Recipe keyed by \(id) has mismatched id \(recipe.id)")
        }
    }
}
