//
//  GameDetailSheet.swift
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
import AppKit
import UniformTypeIdentifiers
import WhiskyKit

struct GameDetailSheet: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(BottleVM.self) private var bottleVM

    @State private var installer: GameInstaller
    @State private var installedGame: InstalledGame?
    @State private var showUninstallConfirm = false
    @State private var steamUsername: String = ""
    @State private var steamPassword: String = ""
    @State private var steamGuardCode: String = ""
    @State private var useAnonymousSteam: Bool = false

    init(recipe: Recipe) {
        self.recipe = recipe
        _installer = State(initialValue: GameInstaller(recipe: recipe))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataGrid
                    if let notes = recipe.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.headline)
                            Text(verbatim: notes)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if recipe.installer == .steam && installedGame == nil {
                        steamCredentialsSection
                    }
                    phaseSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 580, minHeight: 520)
        .onAppear { refreshInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: .macbottleInstalledGamesChanged)) { _ in
            refreshInstalled()
        }
        .confirmationDialog(
            "Remove \(recipe.title) from your library?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "The bottle and its files are kept on disk. Only the MacBottle record is removed.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            CachedAsyncImage(
                url: recipe.iconURL,
                success: { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                },
                placeholder: {
                    ZStack { Rectangle().fill(.quaternary); ProgressView().controlSize(.small) }
                },
                failure: {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "gamecontroller").font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .frame(width: 172, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: recipe.title)
                    .font(.title2.weight(.semibold))
                Text(verbatim: recipe.id)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(20)
    }

    private var metadataGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            metadataRow("Compatibility", value: recipe.compatibility.rawValue.capitalized, tint: tintColor)
            metadataRow("Renderer", value: recipe.renderer.rawValue)
            metadataRow("DirectX", value: recipe.dxVersion.rawValue.uppercased())
            metadataRow("Minimum macOS", value: recipe.minMacOS)
            if let installerKind = recipe.installer {
                metadataRow("Installer", value: installerKind.rawValue.capitalized)
            }
            if !recipe.winetricks.isEmpty {
                metadataRow(
                    "Winetricks",
                    value: recipe.winetricks.joined(separator: ", "),
                    monospaced: true
                )
            }
            if !recipe.env.isEmpty {
                metadataRow(
                    "Environment",
                    value: recipe.env.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"),
                    monospaced: true
                )
            }
        }
    }

    private func metadataRow(
        _ label: String,
        value: String,
        tint: Color? = nil,
        monospaced: Bool = false
    ) -> some View {
        GridRow {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(verbatim: value)
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
    }

    private var tintColor: Color {
        switch recipe.compatibility {
        case .platinum: return .blue
        case .gold:     return .yellow
        case .silver:   return .gray
        case .bronze:   return .orange
        case .broken:   return .red
        }
    }

    @ViewBuilder
    private var phaseSection: some View {
        switch installer.phase {
        case .idle:
            EmptyView()
        case .creatingBottle:
            activePhaseCard(
                title: "Creating bottle",
                systemImage: "shippingbox"
            )
        case .configuringBottle:
            activePhaseCard(
                title: "Configuring bottle",
                systemImage: "gearshape.2"
            )
        case .downloadingSteamSetup:
            activePhaseCard(
                title: "Downloading SteamSetup.exe",
                systemImage: "arrow.down.circle",
                showsLinearProgress: true
            )
        case .nativeSeedingSteam:
            activePhaseCard(
                title: "Native Download Bridge · Steam client",
                systemImage: "bolt.horizontal.circle",
                showsLinearProgress: true
            )
        case .downloadingDepot:
            activePhaseCard(
                title: "Native steamcmd · game depot",
                systemImage: "externaldrive.badge.wifi",
                showsLinearProgress: true
            )
        case .materializingDepot:
            activePhaseCard(
                title: "Cloning depot into bottle",
                systemImage: "internaldrive",
                showsLinearProgress: true
            )
        case .runningInstaller:
            VStack(alignment: .leading, spacing: 12) {
                activePhaseCard(
                    title: recipe.installer == .steam ? "Steam is updating (slow under Wine)" : "Installer running",
                    systemImage: "gearshape.2",
                    indeterminateOnly: true
                )
                if recipe.installer == .steam {
                    Text("Client files were seeded via Native Download Bridge (macOS network stack). Wine only runs Steam UI. Close steam service.exe crash dialogs if they appear — usually harmless.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("I finished installing — continue") {
                    installer.markInstallerFinished()
                }
                .buttonStyle(.borderedProminent)
            }
        case .awaitingMainExe:
            VStack(alignment: .leading, spacing: 8) {
                phaseRow(systemImage: "checkmark.seal", text: "Installer finished. Pick the main game executable.")
                if !installer.statusDetail.isEmpty {
                    Text(verbatim: installer.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Locate main .exe") {
                    pickMainExe()
                }
                .buttonStyle(.bordered)
            }
        case .done:
            phaseRow(systemImage: "checkmark.circle.fill", text: "Installed. You can launch it anytime.", tint: .green)
        case .failed(let message):
            phaseRow(systemImage: "exclamationmark.triangle.fill", text: message, tint: .orange)
        }
    }

    private func activePhaseCard(
        title: String,
        systemImage: String,
        showsLinearProgress: Bool = false,
        indeterminateOnly: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .font(.headline)
                Spacer()
                if let progress = installer.progress, showsLinearProgress {
                    Text(verbatim: "\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if showsLinearProgress {
                ProgressView(value: installer.progress ?? 0)
                    .progressViewStyle(.linear)
            } else if !indeterminateOnly {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if !installer.statusDetail.isEmpty {
                Text(verbatim: installer.statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func phaseRow(systemImage: String, text: String, tint: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(installer.phase.isActive && installer.phase != .runningInstaller)

            if installedGame != nil {
                Button("Uninstall", role: .destructive) { showUninstallConfirm = true }
                    .buttonStyle(.bordered)
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                if installer.phase.isActive {
                    Button("Cancel") {
                        installer.cancelNativeDownload()
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    installer.begin(credentials: makeSteamCredentials())
                } label: {
                    if installer.phase.isActive {
                        Label(activeButtonLabel, systemImage: "arrow.down.to.line")
                    } else {
                        Label(installButtonLabel, systemImage: "arrow.down.to.line")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    installer.phase.isActive
                        || (!isTerminal && installer.phase != .idle)
                        || !canStartSteamInstall
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var activeButtonLabel: String {
        switch installer.phase {
        case .creatingBottle: return "Creating bottle…"
        case .configuringBottle: return "Configuring…"
        case .downloadingSteamSetup: return "Downloading…"
        case .nativeSeedingSteam: return "Seeding Steam…"
        case .downloadingDepot: return "Depot download…"
        case .materializingDepot: return "Cloning depot…"
        case .runningInstaller: return "Starting Steam…"
        default: return installButtonLabel
        }
    }

    private var isTerminal: Bool {
        switch installer.phase {
        case .done, .failed, .idle: return true
        default: return false
        }
    }

    private var installButtonLabel: String {
        switch recipe.installer {
        case .steam: return "Install (native depot)"
        case .gog: return "Install from GOG installer"
        case .custom: return "Install from .exe"
        case .none: return "Install"
        }
    }

    private func refreshInstalled() {
        installedGame = InstalledGameRegistry.shared.game(forRecipe: recipe.id)
    }

    private func uninstall() {
        try? InstalledGameRegistry.shared.remove(recipeID: recipe.id)
        installedGame = nil
        NotificationCenter.default.post(name: .macbottleInstalledGamesChanged, object: nil)
    }

    private func play() {
        guard let installed = installedGame,
              let bottle = bottleVM.bottles.first(where: { $0.url == installed.bottleURL }) else {
            installer.phase = .failed(message: "Backing bottle no longer exists.")
            return
        }
        if let winPath = installed.mainExe, let exeURL = resolveMacURL(forWinPath: winPath, bottle: bottle) {
            let recipe = self.recipe
            Task.detached(priority: .userInitiated) {
                try? await Wine.runProgram(
                    at: exeURL,
                    bottle: bottle,
                    recipe: recipe,
                    autoSelectEngine: true
                )
            }
        } else {
            installer.phase = .failed(message: "Main executable path is invalid.")
        }
    }

    private func pickMainExe() {
        guard let bottleURL = installer.bottleURL,
              let bottle = bottleVM.bottles.first(where: { $0.url == bottleURL }) else {
            installer.phase = .failed(message: "Bottle is no longer available.")
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.exe]
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        if let mainExe = recipe.mainExe {
            let hint = bottle.url
                .appending(path: "drive_c")
                .appending(path: mainExe.replacingOccurrences(of: "\\", with: "/"))
            if FileManager.default.fileExists(atPath: hint.deletingLastPathComponent().path) {
                panel.directoryURL = hint.deletingLastPathComponent()
            }
        }
        panel.prompt = "Select main executable"
        panel.message = "Choose the game's main .exe for \(recipe.title)."
        if panel.runModal() == .OK, let url = panel.url {
            installer.registerMainExecutable(url, bottle: bottle)
            refreshInstalled()
        }
    }

    private func resolveMacURL(forWinPath winPath: String, bottle: Bottle) -> URL? {
        var path = winPath
        if path.hasPrefix("C:\\") || path.hasPrefix("C:/") {
            path = String(path.dropFirst(3))
        }
        path = path.replacingOccurrences(of: "\\", with: "/")
        let url = bottle.url.appending(path: "drive_c").appending(path: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var steamCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Native Depot Plane")
                .font(.headline)
            Text("Game files download through steamcmd on macOS (windows platform), then clone into the bottle. Wine only launches Steam/game.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Anonymous (free / tools only)", isOn: $useAnonymousSteam)
                .toggleStyle(.checkbox)

            if !useAnonymousSteam {
                TextField("Steam username", text: $steamUsername)
                    .textFieldStyle(.roundedBorder)
                SecureField("Steam password", text: $steamPassword)
                    .textFieldStyle(.roundedBorder)
                TextField("Steam Guard code (if asked)", text: $steamGuardCode)
                    .textFieldStyle(.roundedBorder)
            }

            if let appID = SteamAppID.parse(fromRecipeID: recipe.id) {
                Text(verbatim: "AppID \(appID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var canStartSteamInstall: Bool {
        guard recipe.installer == .steam else { return true }
        if useAnonymousSteam { return true }
        return !steamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !steamPassword.isEmpty
    }

    private func makeSteamCredentials() -> SteamCredentials? {
        guard recipe.installer == .steam else { return nil }
        if useAnonymousSteam { return .anonymous }
        let guardCode = steamGuardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return SteamCredentials(
            username: steamUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            password: steamPassword,
            steamGuardCode: guardCode.isEmpty ? nil : guardCode
        )
    }
}
