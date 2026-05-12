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
            bottleURL: bottleVM.bottlesList.paths.first
                ?? bottleVM.bottlesList.defaultBottleDir
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
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
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

        // Install CJK fonts by symlinking macOS system fonts into the
        // bottle's Windows/Fonts directory. This avoids the winetricks
        // Terminal popup and is instant. Without this, any Windows app
        // that renders CJK text (Steam in Chinese, etc.) shows □□□□.
        installCJKFonts(in: bottle)

        Logger.wineKit.info("GameInstaller: applied recipe \(self.recipe.id) to bottle \(bottle.url.lastPathComponent)")
    }

    // swiftlint:disable:next function_body_length
    private func installCJKFonts(in bottle: Bottle) {
        let fontsDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "windows")
            .appending(path: "Fonts")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fontsDir.path) {
            try? fileManager.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        }

        // macOS system fonts that cover CJK glyphs. We symlink rather
        // than copy to save ~100 MB of disk per bottle.
        let systemFonts: [(source: String, dest: String)] = [
            ("/System/Library/Fonts/PingFang.ttc", "pingfang.ttc"),
            ("/System/Library/Fonts/Hiragino Sans GB.ttc", "hiraginosansgb.ttc"),
            ("/System/Library/Fonts/STHeiti Light.ttc", "stheitilight.ttc"),
            ("/System/Library/Fonts/STHeiti Medium.ttc", "stheitimedium.ttc"),
            ("/Library/Fonts/Arial Unicode.ttf", "arialunicode.ttf")
        ]

        for font in systemFonts {
            let dest = fontsDir.appending(path: font.dest)
            guard !fileManager.fileExists(atPath: dest.path) else { continue }
            guard fileManager.fileExists(atPath: font.source) else { continue }
            try? fileManager.createSymbolicLink(
                at: dest,
                withDestinationURL: URL(fileURLWithPath: font.source)
            )
        }

        // Register fonts in the Wine registry so apps discover them.
        let regEntries: [(name: String, file: String)] = [
            ("PingFang SC (TrueType)", "pingfang.ttc"),
            ("Hiragino Sans GB (TrueType)", "hiraginosansgb.ttc"),
            ("STHeiti Light (TrueType)", "stheitilight.ttc"),
            ("STHeiti Medium (TrueType)", "stheitimedium.ttc"),
            ("Arial Unicode MS (TrueType)", "arialunicode.ttf")
        ]

        let regPath = bottle.url
            .appending(path: "drive_c")
            .appending(path: "windows")
            .appending(path: "system.reg")

        // Append font registrations to system.reg if not already present.
        // Wine's registry format is a plain text file; appending entries
        // under the Fonts key is safe and takes effect on next wine start.
        guard var regContent = try? String(contentsOf: regPath, encoding: .utf8) else { return }
        let marker = "[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts]"
        guard regContent.contains(marker) else { return }

        var additions = ""
        for entry in regEntries {
            let key = "\"\(entry.name)\"=\"\(entry.file)\""
            if !regContent.contains(entry.name) {
                additions += "\n\(key)"
            }
        }

        if !additions.isEmpty {
            // Insert after the [Fonts] section header
            if let range = regContent.range(of: marker) {
                let lineEnd = regContent[range.upperBound...].firstIndex(of: "\n") ?? regContent.endIndex
                regContent.insert(contentsOf: additions, at: lineEnd)
                try? regContent.write(to: regPath, atomically: true, encoding: .utf8)
            }
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

// MARK: - Convenience on BottleData for default location

private extension BottleData {
    /// Fallback bottle parent directory when the user has no configured
    /// paths yet — mirrors Whisky's own default.
    var defaultBottleDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier)
            .appending(path: "Bottles")
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let macbottleInstalledGamesChanged = Notification.Name("app.macbottle.installedGamesChanged")
}
