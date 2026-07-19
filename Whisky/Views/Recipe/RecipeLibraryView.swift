//
//  RecipeLibraryView.swift
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

/// Global library of every recipe MacBottle currently knows about.
///
/// This is the "what games can I run on this Mac?" view. It sits at the
/// top of the sidebar as a peer to individual bottles, so the user has a
/// single destination for browsing and searching shipped + synced
/// recipes without drilling into a particular bottle first.
///
/// Reads through `RecipeStore.shared`, which merges bundled recipes with
/// the remote sync cache. The view re-queries on every appear so post-
/// sync additions show up immediately.
struct RecipeLibraryView: View {
    @State private var recipes: [Recipe] = []
    @State private var installedIDs: Set<String> = []
    @State private var query: String = ""
    @State private var selectedRecipe: Recipe?

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 18)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filtered) { recipe in
                    Button {
                        selectedRecipe = recipe
                    } label: {
                        RecipeCard(
                            recipe: recipe,
                            installed: installedIDs.contains(recipe.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(MacBottleTheme.pagePadding)
        }
        .navigationTitle("游戏库")
        .searchable(text: $query, placement: .toolbar, prompt: "搜索游戏 / 配方")
        .overlay {
            if recipes.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task(id: query) {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macbottleRecipesChanged)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macbottleInstalledGamesChanged)) { _ in
            reload()
        }
        .sheet(item: $selectedRecipe) { recipe in
            GameDetailSheet(recipe: recipe)
        }
    }

    private var filtered: [Recipe] {
        guard !query.isEmpty else { return recipes }
        return recipes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var emptyState: some View {
        EmptyStateCard(
            systemImage: "gamecontroller.fill",
            title: "还没有游戏配方",
            message: "点击工具栏同步按钮，从社区获取最新配方。"
        )
    }

    private func reload() {
        let all = RecipeStore.shared.loadAll()
        recipes = all.values.sorted { $0.title.lowercased() < $1.title.lowercased() }
        installedIDs = Set(InstalledGameRegistry.shared.all().map(\.recipeID))
    }
}

/// Single card in the library grid. Shows the cover art, title, platform
/// id, and a color-coded compatibility badge.
private struct RecipeCard: View {
    let recipe: Recipe
    let installed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverArt
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: recipe.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(verbatim: recipe.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    CompatibilityBadge(tier: recipe.compatibility)
                    Text(verbatim: recipe.dxVersion.rawValue.uppercased())
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                    if installed {
                        Text("Installed")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.green)
                    }
                }
            }
            .padding(12)
        }
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(installed ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var coverArt: some View {
        CachedAsyncImage(
            url: recipe.iconURL,
            success: { image in
                image.resizable().aspectRatio(contentMode: .fill)
            },
            placeholder: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    ProgressView().controlSize(.small)
                }
            },
            failure: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "gamecontroller")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
        )
        .aspectRatio(460.0 / 215.0, contentMode: .fit)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
        )
    }
}

private struct CompatibilityBadge: View {
    let tier: CompatibilityTier

    var body: some View {
        Text(verbatim: tier.rawValue.capitalized)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch tier {
        case .platinum: return .blue
        case .gold:     return .yellow
        case .silver:   return .gray
        case .bronze:   return .orange
        case .broken:   return .red
        }
    }
}

/// Notification broadcast when the recipe store contents change (sync
/// apply, manual reset). Views that cache decoded recipes listen for it.
extension Notification.Name {
    static let macbottleRecipesChanged = Notification.Name("app.macbottle.recipesChanged")
}
