//
//  Recipe.swift
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

// MARK: - Recipe

/// A recipe describes how to run a specific Windows game on macOS via a bottle.
///
/// Recipes are authored as JSON files under `WhiskyKit/Sources/WhiskyKit/Recipes/`
/// and shipped inside the WhiskyKit bundle as embedded resources. See
/// `docs/RECIPE_AUTHORING.md` for the contribution workflow and
/// `docs/recipe.v1.schema.json` for the machine-readable schema.
///
/// The `Recipe` type is intentionally flat and append-only: new optional
/// fields may be added, existing fields are never renamed or removed. The
/// `schema` field identifies the contract version.
public struct Recipe: Codable, Hashable, Sendable, Identifiable {
    /// Schema contract version. Currently always `1`.
    public let schema: Int

    /// Stable machine identifier. Convention: `<platform>.<platformID>`.
    ///
    /// Examples:
    /// - `steam.2050650`   — Black Myth: Wukong on Steam
    /// - `gog.1207658924`  — The Witcher 3 on GOG
    /// - `generic.skyrim-se` — installer-based or out-of-platform title
    public let id: String

    /// Human-readable title. Not localized at the recipe level; we localize
    /// display strings in the UI layer based on the bottle's locale.
    public let title: String

    /// Optional HTTPS URL to a game icon image (PNG or JPEG, ~460×215 or
    /// square, under 200 KB recommended). Rendered in the program settings
    /// UI. When missing the UI falls back to a neutral SF Symbol glyph.
    ///
    /// For Steam titles, conventional sources are
    /// `https://cdn.cloudflare.steamstatic.com/steam/apps/<appid>/header.jpg`
    /// or `.../library_600x900.jpg`. Recipe authors are free to host the
    /// icon anywhere HTTPS-reachable, but the URL is fetched by the client
    /// at runtime so its availability directly affects user experience.
    public let iconURL: URL?

    /// DirectX API requirement of the game. Affects renderer selection.
    public let dxVersion: DXVersion

    /// Minimum macOS version required. Semantic version, e.g. `14.0`.
    public let minMacOS: String

    /// Preferred renderer backend. See `RecipeRenderer`.
    public let renderer: RecipeRenderer

    /// Optional list of winetricks verbs required before first launch.
    ///
    /// Examples: `vcrun2022`, `dotnet48`, `corefonts`.
    public let winetricks: [String]

    /// Environment variables that must be set when launching the game.
    ///
    /// These are merged on top of the bottle's own settings. Recipe env
    /// wins on conflicts, because the recipe is the narrower, more
    /// game-specific source of truth.
    public let env: [String: String]

    /// Optional Windows registry modifications applied before first launch.
    public let registry: [RegistryEntry]

    /// Human-authored compatibility tier. See `CompatibilityTier`.
    public let compatibility: CompatibilityTier

    /// Free-form notes shown to the user in the UI. May contain Markdown.
    /// Kept short; long explanations belong in the game's README sidecar.
    public let notes: String?

    public init(
        schema: Int = 1,
        id: String,
        title: String,
        iconURL: URL? = nil,
        dxVersion: DXVersion,
        minMacOS: String,
        renderer: RecipeRenderer,
        winetricks: [String] = [],
        env: [String: String] = [:],
        registry: [RegistryEntry] = [],
        compatibility: CompatibilityTier,
        notes: String? = nil
    ) {
        self.schema = schema
        self.id = id
        self.title = title
        self.iconURL = iconURL
        self.dxVersion = dxVersion
        self.minMacOS = minMacOS
        self.renderer = renderer
        self.winetricks = winetricks
        self.env = env
        self.registry = registry
        self.compatibility = compatibility
        self.notes = notes
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case schema
        case id
        case title
        case iconURL = "icon_url"
        case dxVersion = "dx_version"
        case minMacOS = "min_macos"
        case renderer
        case winetricks
        case env
        case registry
        case compatibility
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try container.decode(Int.self, forKey: .schema)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
        self.dxVersion = try container.decode(DXVersion.self, forKey: .dxVersion)
        self.minMacOS = try container.decode(String.self, forKey: .minMacOS)
        self.renderer = try container.decode(RecipeRenderer.self, forKey: .renderer)
        self.winetricks = try container.decodeIfPresent([String].self, forKey: .winetricks) ?? []
        self.env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        self.registry = try container.decodeIfPresent([RegistryEntry].self, forKey: .registry) ?? []
        self.compatibility = try container.decode(CompatibilityTier.self, forKey: .compatibility)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

// MARK: - Supporting types

public enum DXVersion: String, Codable, CaseIterable, Sendable {
    case d3d9, d3d10, d3d11, d3d12, vulkan, opengl
}

public enum RecipeRenderer: String, Codable, CaseIterable, Sendable {
    /// Apple's Game Porting Toolkit (D3DMetal). Default for DX11/12 on Apple Silicon.
    case d3dmetal
    /// DXVK (DirectX → Vulkan → Metal via MoltenVK). Useful for DX10/11 on Intel.
    case dxvk
    /// Wine's built-in DirectX → OpenGL translation. Last resort.
    case wined3d
}

/// Compatibility tier mirrors ProtonDB's five-level scale.
///
/// - `platinum`: runs perfectly out of the box
/// - `gold`: runs perfectly with minor tweaks
/// - `silver`: playable with noticeable issues
/// - `bronze`: runs but with significant issues
/// - `broken`: does not run or crashes on launch
public enum CompatibilityTier: String, Codable, CaseIterable, Sendable {
    case platinum
    case gold
    case silver
    case bronze
    case broken
}

public struct RegistryEntry: Codable, Hashable, Sendable {
    public enum ValueType: String, Codable, Sendable {
        case string  = "REG_SZ"
        case dword   = "REG_DWORD"
        case binary  = "REG_BINARY"
    }

    public let path: String
    public let key: String
    public let type: ValueType
    public let value: String

    public init(path: String, key: String, type: ValueType, value: String) {
        self.path = path
        self.key = key
        self.type = type
        self.value = value
    }
}
