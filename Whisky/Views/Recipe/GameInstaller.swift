//
//  GameInstaller.swift
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

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit
import SemanticVersion
import os.log

/// Phase reported back to the UI during an install flow.
enum InstallPhase: Equatable {
    case idle
    case creatingBottle
    case downloadingSteamSetup
    case runningInstaller
    case awaitingMainExe(bottleURL: URL)
    case done(InstalledGame)
    case failed(message: String)
}

/// Coordinates the end-to-end install flow for a recipe: bottle
/// creation, recipe env application, installer launch, and pairing the
/// resulting main executable with an `InstalledGame` record.
///
/// Kept as a `@MainActor` observable object so SwiftUI can drive a
/// progress UI against its `phase` property without cross-actor hops.
@MainActor
final class GameInstaller: ObservableObject {
    @Published var phase: InstallPhase = .idle

    /// The bottle directory created for this install. Non-nil once the
    /// creatingBottle step has succeeded; UI uses this to show "Open
    /// bottle in advanced view" even before the user finishes installing.
    @Published var bottleURL: URL?

    private let recipe: Recipe
    private let bottleVM: BottleVM
    private let registry: InstalledGameRegistry

    init(
        recipe: Recipe,
        bottleVM: BottleVM = .shared,
        registry: InstalledGameRegistry = .shared
    ) {
        self.recipe = recipe
        self.bottleVM = bottleVM
        self.registry = registry
    }

    // MARK: - Entry point

    /// Full install flow. Each step may surface back to the UI: the
    /// Steam flow will call `installerSucceeded()` when the user has
    /// finished inside Steam and is ready to pick the main .exe; the
    /// GOG and custom flows wait for a file pick before even launching
    /// the installer.
    func begin() {
        Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        guard recipe.installer != nil else {
            phase = .failed(message: "Recipe has no installer configured.")
            return
        }

        phase = .creatingBottle
        let url = bottleVM.createNewBottle(
            bottleName: recipe.title,
            winVersion: .win10,
            // Always create new bottles under the default parent. Using
            // an existing bottle path as the parent (which was happening
            // when we took `paths.first`) produced nested bottles like
            // `Bottles/<existing-UUID>/<new-UUID>`.
            bottleURL: BottleData.defaultBottleDir
        )
        bottleURL = url

        // Wait until the bottle is registered and wine has initialised
        // its prefix. BottleVM does this asynchronously; we poll rather
        // than add a new callback API to keep the change surface small.
        let bottle = await waitForBottle(url: url)
        guard let bottle else {
            phase = .failed(message: "Bottle creation timed out.")
            return
        }

        // Wait for drive_c/windows to exist (Wine prefix init is async)
        let windowsDir = bottle.url.appending(path: "drive_c").appending(path: "windows")
        let windowsReady = await waitForPath(windowsDir, timeout: 30)
        if !windowsReady {
            Logger.wineKit.warning("GameInstaller: drive_c/windows not found after 30s, skipping font install")
        }

        await applyRecipeSettings(to: bottle)

        switch recipe.installer {
        case .steam:
            await runSteamInstaller(bottle: bottle)
        case .gog, .custom, .none:
            await runPickedInstaller(bottle: bottle)
        }
    }

    // MARK: - Post-install pairing

    /// Called by the UI after the user clicks "I installed it, pick the
    /// main .exe" to associate an executable with the install record.
    func registerMainExecutable(_ exeURL: URL, bottle: Bottle) {
        do {
            let winPath = wineStylePath(for: exeURL, inBottle: bottle)
            let game = InstalledGame(
                recipeID: recipe.id,
                bottleURL: bottle.url,
                mainExe: winPath
            )
            try registry.record(game)
            phase = .done(game)
            NotificationCenter.default.post(name: .macbottleInstalledGamesChanged, object: nil)
        } catch {
            phase = .failed(message: "Failed to register game: \(error.localizedDescription)")
        }
    }

    // MARK: - Steam flow

    private static let steamSetupURL: URL = {
        guard let url = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe") else {
            preconditionFailure("static Steam setup URL")
        }
        return url
    }()

    private func runSteamInstaller(bottle: Bottle) async {
        phase = .downloadingSteamSetup
        let tempSetup: URL
        do {
            tempSetup = try await downloadSteamSetup()
        } catch {
            phase = .failed(message: "Could not download SteamSetup.exe: \(error.localizedDescription)")
            return
        }

        phase = .runningInstaller
        do {
            try await Wine.runProgram(at: tempSetup, bottle: bottle)
        } catch {
            phase = .failed(message: "Steam installer failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempSetup)
            return
        }
        try? FileManager.default.removeItem(at: tempSetup)

        phase = .awaitingMainExe(bottleURL: bottle.url)
    }

    private func downloadSteamSetup() async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        let (temp, _) = try await session.download(from: Self.steamSetupURL)
        let dest = FileManager.default.temporaryDirectory
            .appending(path: "SteamSetup-\(UUID().uuidString).exe")
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }

    // MARK: - GOG / custom flow

    private func runPickedInstaller(bottle: Bottle) async {
        let picked = await pickInstallerExe()
        guard let picked else {
            phase = .failed(message: "Installer selection cancelled.")
            return
        }

        phase = .runningInstaller
        do {
            try await Wine.runProgram(at: picked, bottle: bottle)
        } catch {
            phase = .failed(message: "Installer failed: \(error.localizedDescription)")
            return
        }
        phase = .awaitingMainExe(bottleURL: bottle.url)
    }

    @MainActor
    private func pickInstallerExe() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.exe, UTType(exportedAs: "com.microsoft.msi-installer")]
        panel.prompt = "Select installer"
        panel.message = "Choose the Windows installer for \(recipe.title)."
        let response = await withCheckedContinuation { continuation in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }
        guard response == .OK else { return nil }
        return panel.url
    }

    // MARK: - Helpers

    private func applyRecipeSettings(to bottle: Bottle) async {
        bottle.settings.dxvk = (recipe.renderer == .dxvk)

        // Register CJK font substitutions so Windows apps that request
        // SimSun / MS Song / Microsoft YaHei get rendered with macOS
        // system fonts instead of showing □□□□ boxes.
        await installCJKFontSubstitutions(bottle: bottle)

        Logger.wineKit.info("GameInstaller: applied recipe \(self.recipe.id) to bottle \(bottle.url.lastPathComponent)")
    }

    // swiftlint:disable:next function_body_length
    private func installCJKFontSubstitutions(bottle: Bottle) async {
        // Step 1: Copy the bundled WenQuanYi Micro Hei font into the
        // bottle's Fonts directory for Chromium-based apps (Steam UI).
        let fontsDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "windows")
            .appending(path: "Fonts")
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fontsDir.path(percentEncoded: false)) {
            try? fileManager.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        }

        if let bundledFont = Bundle.main.url(forResource: "wqy-microhei", withExtension: "ttc") {
            let dest = fontsDir.appending(path: "wqy-microhei.ttc")
            if !fileManager.fileExists(atPath: dest.path(percentEncoded: false)) {
                try? fileManager.copyItem(at: bundledFont, to: dest)
            }
        }

        // Step 2: Register font substitutions pointing to BOTH STHeiti
        // (macOS system font, works immediately for GDI apps) AND
        // WenQuanYi (for apps that enumerate Fonts/ directory).
        // STHeiti is the primary because Wine already knows about it
        // via the Z: drive mapping — no font cache rebuild needed.
        let substitutions: [(windows: String, replacement: String)] = [
            ("SimSun", "STHeiti"),
            ("NSimSun", "STHeiti"),
            ("Microsoft YaHei", "STHeiti"),
            ("Microsoft YaHei UI", "STHeiti"),
            ("宋体", "STHeiti"),
            ("新宋体", "STHeiti"),
            ("MS UI Gothic", "STHeiti"),
            ("MS Gothic", "STHeiti"),
            ("Gulim", "STHeiti"),
            ("Batang", "STHeiti")
        ]

        for sub in substitutions {
            do {
                try await Wine.runWine(
                    ["reg", "add",
                     #"HKCU\Software\Wine\Fonts\Replacements"#,
                     "-v", sub.windows, "-t", "REG_SZ",
                     "-d", sub.replacement, "-f"],
                    bottle: bottle
                )
            } catch {
                Logger.wineKit.debug(
                    "GameInstaller: font sub \(sub.windows) failed: \(error.localizedDescription)"
                )
            }
        }

        // Step 3: Register WenQuanYi in the Windows Fonts registry so
        // Chromium/CEF can find it when scanning installed fonts.
        do {
            try await Wine.runWine(
                ["reg", "add",
                 #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts"#,
                 "-v", "WenQuanYi Micro Hei (TrueType)",
                 "-t", "REG_SZ", "-d", "wqy-microhei.ttc", "-f"],
                bottle: bottle
            )
        } catch {
            Logger.wineKit.debug("GameInstaller: font registration failed: \(error.localizedDescription)")
        }
    }

    private func waitForBottle(url: URL, timeout: TimeInterval = 30) async -> Bottle? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let bottle = bottleVM.bottles.first(where: { $0.url == url && $0.isAvailable }) {
                return bottle
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return nil
    }

    private func waitForPath(_ url: URL, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// Convert a macOS file URL living under a bottle's drive_c to the
    /// `C:\...` form wine expects. Returns the macOS path as-is if the
    /// file is outside drive_c (which would be unusual).
    private func wineStylePath(for url: URL, inBottle bottle: Bottle) -> String {
        let driveC = bottle.url.appending(path: "drive_c").path(percentEncoded: false)
        let absolute = url.path(percentEncoded: false)
        guard absolute.hasPrefix(driveC) else {
            return absolute
        }
        let relative = String(absolute.dropFirst(driveC.count))
            .replacingOccurrences(of: "/", with: "\\")
        return "C:" + relative
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let macbottleInstalledGamesChanged = Notification.Name("app.macbottle.installedGamesChanged")
}
