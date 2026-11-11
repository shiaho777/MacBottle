//
//  RecipeLibraryView.swift
//  MacBottle
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
import MacBottleKit

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
    var resetToken: Int = 0
    var openBottle: (URL) -> Void = { _ in }

    @State private var recipes: [Recipe] = []
    @State private var installedIDs: Set<String> = []
    @State private var installedGames: [InstalledGame] = []
    @State private var query: String = ""
    @State private var filter: LibraryFilter = .all
    @State private var selectedRecipe: Recipe?
    @State private var installRequest: InstallRequest?

    private struct InstallRequest: Identifiable {
        let id = UUID()
        let recipe: Recipe
        let installerURL: URL
    }

    private enum LibraryFilter: Hashable {
        case all
        case installed
        case tier(CompatibilityTier)

        var title: LocalizedStringKey {
            switch self {
            case .all: return "library.filter.all"
            case .installed: return "library.filter.installed"
            case .tier(.platinum): return "compatibility.platinum"
            case .tier(.gold): return "compatibility.gold"
            case .tier(.silver): return "compatibility.silver"
            case .tier(.bronze): return "compatibility.bronze"
            case .tier(.broken): return "compatibility.broken"
            }
        }

        func matches(_ recipe: Recipe, installedIDs: Set<String>) -> Bool {
            switch self {
            case .all:
                return true
            case .installed:
                return installedIDs.contains(recipe.id)
            case .tier(let tier):
                return recipe.compatibility == tier
            }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 18)
    ]

    private var filterOptions: [LibraryFilter] {
        [
            .all,
            .installed,
            .tier(.platinum),
            .tier(.gold),
            .tier(.silver),
            .tier(.bronze),
            .tier(.broken)
        ]
    }

    var body: some View {
        content
            .background(AppBackground())
            .defaultScrollAnchor(.top)
            .id(resetToken)
            .navigationTitle("library.title")
            .navigationSubtitle(Text(verbatim: statsLine))
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
                }
            }
            .task {
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

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacBottleTheme.sectionSpacing) {
                headerSection
                libraryToolbar
                resultsSection
            }
            .padding(.horizontal, MacBottleTheme.pagePadding)
            .padding(.top, MacBottleTheme.pagePadding)
            .padding(.bottom, AppSpacing.doubleExtraLarge)
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        if continueGames.isEmpty {
            welcomeCard
        } else {
            continueSection
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if filtered.isEmpty {
            filteredEmptyState
        } else {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(filtered) { recipe in
                    recipeCell(recipe)
                }
            }
        }
    }

    private func recipeCell(_ recipe: Recipe) -> some View {
        Button {
            selectedRecipe = recipe
        } label: {
            RecipeCard(
                recipe: recipe,
                installed: installedIDs.contains(recipe.id)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(recipe.title))
        .contextMenu {
            Button("library.details", systemImage: "info.circle") {
                selectedRecipe = recipe
            }
            if let game = installedGames.first(where: { $0.recipeID == recipe.id }) {
                Button("library.openBottle", systemImage: "shippingbox") {
                    openBottle(game.bottleURL)
                }
            }
            Divider()
            Button("library.copyID", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recipe.id, forType: .string)
            }
        }
    }

    private var installedVisibleCount: Int {
        recipes.filter { installedIDs.contains($0.id) }.count
    }

    private var statsLine: String {
        String(
            format: String(localized: "library.stats %lld %lld"),
            recipes.count,
            installedVisibleCount
        )
    }

    private var continueGames: [InstalledGame] {
        installedGames
            .filter { game in recipes.contains(where: { $0.id == game.recipeID }) }
            .sorted { $0.installedAt > $1.installedAt }
            .prefix(4)
            .map { $0 }
    }

    private var filtered: [Recipe] {
        recipes.filter { recipe in
            let matchesQuery = query.isEmpty
                || recipe.title.localizedCaseInsensitiveContains(query)
                || recipe.id.localizedCaseInsensitiveContains(query)
            return matchesQuery && filter.matches(recipe, installedIDs: installedIDs)
        }
    }

    private var welcomeCard: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text("library.welcome.title")
                    .font(.title3.weight(.bold))
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
            .tint(Color.accentColor)
            .controlSize(.large)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.10), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("library.continue.title")
                    .font(.headline)
                Spacer()
                Text(verbatim: "\(continueGames.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueGames) { game in
                        if let recipe = recipes.first(where: { $0.id == game.recipeID }) {
                            ContinuePlayingCard(
                                recipe: recipe,
                                bottleName: bottleName(for: game.bottleURL)
                            ) {
                                openBottle(game.bottleURL)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var libraryToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("library.browse")
                    .font(.headline)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filterOptions, id: \.self) { option in
                        AppFilterChip(
                            title: option.title,
                            isSelected: filter == option,
                            count: count(for: option)
                        ) {
                            withAnimation(AppMotion.standard) {
                                filter = option
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("library.empty.filtered.title")
                .font(.title3.weight(.semibold))
            Text("library.empty.filtered.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("library.empty.filtered.reset") {
                withAnimation(AppMotion.standard) {
                    filter = .all
                    query = ""
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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
        .background(AppBackground())
    }

    private func count(for option: LibraryFilter) -> Int {
        recipes.filter { option.matches($0, installedIDs: installedIDs) }.count
    }

    private func bottleName(for url: URL) -> String {
        BottleVM.shared.bottles
            .first(where: { $0.url == url })?
            .settings.name ?? url.lastPathComponent
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
        installedGames = InstalledGameRegistry.shared.all()
        installedIDs = Set(installedGames.map(\.recipeID))
    }
}

/// A wide, low card in the Continue-playing rail.
private struct ContinuePlayingCard: View {
    let recipe: Recipe
    let bottleName: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
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
                                .foregroundStyle(.secondary)
                        }
                    }
                )
                .frame(width: 104, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: recipe.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: bottleName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    CompatibilityBadge(tier: recipe.compatibility)
                }

                Spacer(minLength: 6)

                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 6, y: 2)
            }
            .padding(10)
            .frame(width: 310, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                    .fill(.background.secondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
            }
            .scaleEffect(hovering ? 1.012 : 1)
            .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: hovering ? 10 : 0, y: hovering ? 4 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.standard, value: hovering)
        .accessibilityLabel(Text(recipe.title))
        .accessibilityHint(Text("library.continue.title"))
    }
}

/// Single card in the library grid. Shows the cover art, title, platform
/// id, and color-coded compatibility / renderer badges.
private struct RecipeCard: View {
    let recipe: Recipe
    let installed: Bool

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverArt
                .overlay(alignment: .topTrailing) {
                    if installed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white, Color.green)
                            .padding(8)
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: recipe.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    CompatibilityBadge(tier: recipe.compatibility)
                    RendererBadge(renderer: recipe.renderer)
                    Spacer(minLength: 0)
                }

                Text(verbatim: recipe.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(12)
        }
        .background {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .fill(.background.secondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .strokeBorder(
                    installed
                        ? Color.green.opacity(0.35)
                        : Color(nsColor: .separatorColor).opacity(0.42),
                    lineWidth: 0.5
                )
        }
        .scaleEffect(hovering ? 1.012 : 1)
        .shadow(
            color: .black.opacity(hovering ? 0.16 : 0.04),
            radius: hovering ? 16 : 2,
            y: hovering ? 7 : 1
        )
        .onHover { hovering = $0 }
        .animation(AppMotion.standard, value: hovering)
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
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.16)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: MacBottleTheme.cardRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: MacBottleTheme.cardRadius
            )
        )
    }
}

/// Notification broadcast when the recipe store contents change (sync
/// apply, manual reset). Views that cache decoded recipes listen for it.
extension Notification.Name {
    static let macbottleRecipesChanged = Notification.Name("app.macbottle.recipesChanged")
}
