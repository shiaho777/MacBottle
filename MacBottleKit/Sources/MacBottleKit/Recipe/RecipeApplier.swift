//
//  RecipeApplier.swift
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

import Foundation

/// Applies a recipe's runtime overrides to the environment used when
/// launching a program.
///
/// The applier is intentionally a pure function over dictionaries: it does
/// not touch the file system, does not spawn processes, and does not mutate
/// `Bottle` state. This keeps it trivially testable and predictable, which
/// matters because every single game launch routes through it.
///
/// Side-effectful parts of applying a recipe — running winetricks verbs,
/// writing registry entries — are the responsibility of a separate
/// `RecipeProvisioner` that runs once per bottle-recipe pairing at mount
/// time, not on every launch.
public enum RecipeApplier {
    /// Merge the recipe's environment variables on top of an existing
    /// environment dictionary.
    ///
    /// Recipe values always win on conflict. The rationale: a recipe is
    /// game-specific and community-vetted; the bottle-level defaults are
    /// broader and therefore weaker. Users who want the opposite behaviour
    /// can detach the recipe from the bottle.
    ///
    /// - Parameters:
    ///   - recipe: the recipe to apply, or `nil` for a no-op merge.
    ///   - environment: existing environment to merge into.
    /// - Returns: a new environment dictionary with recipe overrides applied.
    public static func apply(
        _ recipe: Recipe?,
        to environment: [String: String]
    ) -> [String: String] {
        guard let recipe else { return environment }
        var merged = environment
        for (key, value) in recipe.env {
            merged[key] = value
        }
        return merged
    }
}
