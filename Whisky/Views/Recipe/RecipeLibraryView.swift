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

import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
    @State private var installRequest: InstallRequest?

    private struct InstallRequest: Identifiable {
        let id = UUID()
        let recipe: Recipe
        let installerURL: URL
    }

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 18)]

    var body: some View {
        VStack(spacing: 0) {
            if installedIDs.isEmpty {
                welcomeCard
                    .padding(.horizontal, MacBottleTheme.pagePadding)
                    .padding(.top, MacBottleTheme.pagePadding)
            }
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
        }
        .navigationTitle("library.title")
        .searchable(text: $query, placement: .toolbar, prompt: "library.search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    pickInstaller()
                } label: {
                    Label("library.installExe", systemImage: "plus.app")
                }
                .help("library.installExe")
            }
        }
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
        .sheet(item: $installRequest) { request in
            GameDetailSheet(recipe: request.recipe, installerURL: request.installerURL)
        }
    }

    private var filtered: [Recipe] {
        guard !query.isEmpty else { return recipes }
        return recipes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var welcomeCard: some View {
        SurfaceCard(padding: 18) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: MacBottleTheme.tileRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("library.welcome.title")
                        .font(.title3.weight(.semibold))
                    Text("library.welcome.message")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("library.installExe") {
                    pickInstaller()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateCard(
            systemImage: "gamecontroller.fill",
            title: "library.empty.title",
            message: "library.empty.message",
            actionTitle: "library.installExe"
        ) {
            pickInstaller()
        }
    }

    private func pickInstaller() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "exe") ?? .data,
            UTType(filenameExtension: "msi") ?? .data
        ].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        panel.message = String(localized: "library.installExe.panel")
        panel.prompt = String(localized: "library.installExe.prompt")
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let title = url.deletingPathExtension().lastPathComponent
            let recipe = Recipe(
                id: "generic.\(UUID().uuidString.lowercased())",
                title: title,
                dxVersion: .d3d11,
                minMacOS: "14.0",
                renderer: .d3dmetal,
                installer: .custom,
                compatibility: .silver
            )
            installRequest = InstallRequest(recipe: recipe, installerURL: url)
        }
    }

    private func reload() {
        let all = RecipeStore.shared.loadAll()
        recipes = all.values.sorted { $0.title.lowercased() < $1.title.lowercased() }
        _ = InstalledGameRegistry.shared.reconcileExistingBottles()
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
                        Text("library.installed")
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
                image.resizable().scaledToFill()
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
        Text(verbatim: tier.localizedName)
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
