//
//  RecipeSection.swift
//  Whisky
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

import SwiftUI
import WhiskyKit

/// Per-program section that lets the user pick a shipped recipe.
///
/// A recipe is a JSON document under
/// `WhiskyKit/Sources/WhiskyKit/Recipes/` describing how to run a specific
/// Windows game. When attached to a program, the recipe's environment
/// overrides are merged into the program's launch env by
/// `Program.generateEnvironment()`. See `docs/ARCHITECTURE.md`.
struct RecipeSection: View {
    @Bindable var program: Program
    @Binding var isExpanded: Bool

    /// Sorted for a stable picker order. Reloaded on appear and whenever
    /// the store changes (remote sync apply), so newly synced recipes are
    /// pickable without recreating the view.
    @State private var recipes: [Recipe] = []

    var body: some View {
        Section("recipe.section.header", isExpanded: $isExpanded) {
            Picker("recipe.section.attach", selection: recipeIDBinding) {
                Text("recipe.section.none").tag(String?.none)
                ForEach(recipes) { recipe in
                    Text(verbatim: "\(recipe.title)  ·  \(recipe.compatibility.rawValue)")
                        .tag(Optional(recipe.id))
                }
            }

            if let recipe = attachedRecipe {
                RecipeHeaderView(recipe: recipe)
                RecipeDetailRows(recipe: recipe)
            } else {
                Text("recipe.section.help")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macbottleRecipesChanged)) { _ in
            reload()
        }
    }

    private func reload() {
        recipes = RecipeStore.shared
            .loadAll()
            .values
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    private var recipeIDBinding: Binding<String?> {
        Binding(
            get: { program.settings.recipeID },
            set: { program.settings.recipeID = $0 }
        )
    }

    private var attachedRecipe: Recipe? {
        guard let id = program.settings.recipeID else { return nil }
        return recipes.first { $0.id == id }
    }
}

/// Read-only summary of the selected recipe's key fields.
private struct RecipeDetailRows: View {
    let recipe: Recipe

    var body: some View {
        LabeledContent("recipe.section.compatibility") {
            Text(verbatim: recipe.compatibility.rawValue.capitalized)
                .foregroundStyle(color(for: recipe.compatibility))
        }
        LabeledContent("recipe.section.renderer") {
            Text(verbatim: recipe.renderer.rawValue)
        }
        LabeledContent("recipe.section.directx") {
            Text(verbatim: recipe.dxVersion.rawValue)
        }
        if !recipe.winetricks.isEmpty {
            LabeledContent("recipe.section.winetricks") {
                Text(verbatim: recipe.winetricks.joined(separator: ", "))
                    .font(.system(.callout, design: .monospaced))
            }
        }
        if !recipe.env.isEmpty {
            LabeledContent("recipe.section.envVars") {
                Text(verbatim: "\(recipe.env.count)")
                    .foregroundStyle(.secondary)
            }
        }
        if let notes = recipe.notes, !notes.isEmpty {
            Text(verbatim: notes)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(for tier: CompatibilityTier) -> Color {
        switch tier {
        case .platinum: return .blue
        case .gold:     return .yellow
        case .silver:   return .gray
        case .bronze:   return .orange
        case .broken:   return .red
        }
    }
}

/// Large header row with the recipe's title and cover art.
///
/// Icons are fetched asynchronously from the URL declared in the recipe.
/// Failures fall back to a neutral SF Symbol so the UI stays coherent
/// whether or not the network is reachable — by design the app must be
/// fully usable offline with only bundled recipes.
private struct RecipeHeaderView: View {
    let recipe: Recipe

    // Steam header art is 460×215; cap the displayed height so the row
    // stays compact even on very tall cover art from other sources.
    private static let artHeight: CGFloat = 72

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = recipe.iconURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            fallbackGlyph
                        case .empty:
                            ProgressView().controlSize(.small)
                        @unknown default:
                            fallbackGlyph
                        }
                    }
                } else {
                    fallbackGlyph
                }
            }
            .frame(width: Self.artHeight * (460.0 / 215.0), height: Self.artHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: recipe.title)
                    .font(.headline)
                Text(verbatim: recipe.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var fallbackGlyph: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "gamecontroller")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
