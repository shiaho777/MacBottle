//
//  RecipeValidator.swift
//  MacBottleKit
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

/// Semantic checks that decoding alone cannot express.
///
/// `Recipe` is `Codable`, so `RecipeLint` used to prove only that a file
/// parses. A recipe declaring `dx_version: d3d12` with
/// `renderer: wined3d` decoded happily and then selected a renderer that
/// cannot run the game.
public enum RecipeValidator {
    public static func errors(for recipe: Recipe) -> [String] {
        var errors: [String] = []

        if recipe.schema != 1 {
            errors.append("unsupported schema \(recipe.schema); expected 1")
        }
        if !isValidID(recipe.id) {
            errors.append("id '\(recipe.id)' must look like <steam|gog|generic>.<stable-id>")
        }
        if !isValidVersion(recipe.minMacOS) {
            errors.append("min_macos '\(recipe.minMacOS)' must be major.minor")
        }
        if recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("title must not be empty")
        }
        if let installer = recipe.installer {
            switch installer {
            case .steam where !recipe.id.hasPrefix("steam."):
                errors.append("installer 'steam' requires a steam.* id")
            case .gog where !recipe.id.hasPrefix("gog."):
                errors.append("installer 'gog' requires a gog.* id")
            default:
                break
            }
        }
        for verb in recipe.winetricks where verb.isEmpty
            || verb.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            errors.append("winetricks verb '\(verb)' must be a single token")
        }
        for entry in recipe.registry {
            if !entry.path.uppercased().hasPrefix("HKEY_") {
                errors.append("registry path '\(entry.path)' must start with HKEY_")
            }
            if entry.key.isEmpty {
                errors.append("registry key must not be empty")
            }
        }
        if let mainExe = recipe.mainExe {
            if mainExe.contains("..") || mainExe.hasPrefix("/") {
                errors.append("main_exe '\(mainExe)' must be a relative path inside drive_c")
            }
        }
        errors.append(contentsOf: rendererErrors(for: recipe))
        return errors
    }

    public static func validate(_ recipe: Recipe) throws {
        let problems = errors(for: recipe)
        guard problems.isEmpty else {
            throw RecipeValidationError.invalid(id: recipe.id, problems: problems)
        }
    }

    private static func rendererErrors(for recipe: Recipe) -> [String] {
        switch (recipe.dxVersion, recipe.renderer) {
        case (.d3d12, .d3dmetal), (.d3d12, .vkd3d):
            return []
        case (.d3d12, _):
            return ["d3d12 requires d3dmetal or vkd3d; \(recipe.renderer.rawValue) cannot run it"]
        case (.d3d11, .d3dmetal), (.d3d11, .dxvk), (.d3d11, .wined3d), (.d3d11, .dxmt):
            return []
        case (.d3d11, _):
            return ["d3d11 cannot use \(recipe.renderer.rawValue); use d3dmetal, dxmt, dxvk, or wined3d"]
        case (.d3d10, .dxvk), (.d3d10, .wined3d):
            return []
        case (.d3d10, _):
            return ["d3d10 cannot use \(recipe.renderer.rawValue); use dxvk or wined3d"]
        case (.d3d9, .dxvk), (.d3d9, .wined3d),
             (.opengl, .dxvk), (.opengl, .wined3d):
            return []
        case (.d3d9, _), (.opengl, _):
            return ["\(recipe.dxVersion.rawValue) cannot use \(recipe.renderer.rawValue); use dxvk or wined3d"]
        case (.vulkan, .moltenvk):
            return []
        case (.vulkan, _):
            return ["vulkan requires the moltenvk renderer; DXVK is not in the Vulkan path"]
        }
    }

    private static func isValidID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty else { return false }
        guard ["steam", "gog", "generic"].contains(String(parts[0])) else { return false }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_."))
        return parts[1].unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isValidVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}

public enum RecipeValidationError: Error, LocalizedError {
    case invalid(id: String, problems: [String])

    public var errorDescription: String? {
        switch self {
        case .invalid(let id, let problems):
            return "Recipe \(id) is invalid: \(problems.joined(separator: "; "))"
        }
    }
}
