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
import Observation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit
import SemanticVersion
import os.log

enum InstallPhase: Equatable {
    case idle
    case creatingBottle
    case configuringBottle
    case downloadingSteamSetup
    case nativeSeedingSteam
    case downloadingDepot
    case materializingDepot
    case runningInstaller
    case awaitingMainExe(bottleURL: URL)
    case done(InstalledGame)
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .creatingBottle, .configuringBottle, .downloadingSteamSetup,
                .nativeSeedingSteam, .downloadingDepot, .materializingDepot, .runningInstaller:
            return true
        default:
            return false
        }
    }
}

@MainActor
@Observable
final class GameInstaller {
    var phase: InstallPhase = .idle
    var bottleURL: URL?
    var statusDetail: String = ""
    var progress: Double?

    private let recipe: Recipe
    private let bottleVM: BottleVM
    private let registry: InstalledGameRegistry
    private var workTask: Task<Void, Never>?

    init(
        recipe: Recipe,
        bottleVM: BottleVM = .shared,
        registry: InstalledGameRegistry = .shared
    ) {
        self.recipe = recipe
        self.bottleVM = bottleVM
        self.registry = registry
    }

    private var pendingCredentials: SteamCredentials?

    func begin(credentials: SteamCredentials? = nil) {
        guard !phase.isActive else { return }
        workTask?.cancel()
        progress = nil
        statusDetail = ""
        pendingCredentials = credentials
        workTask = Task { [weak self] in
            await self?.run()
        }
    }

    func cancelNativeDownload() {
        DownloadBridge.cancelDepotDownload()
        workTask?.cancel()
        if phase.isActive {
            fail("Cancelled.")
        }
    }

    func markInstallerFinished() {
        guard let url = bottleURL else { return }
        phase = .awaitingMainExe(bottleURL: url)
        statusDetail = "Pick the main game executable to finish."
        progress = nil
    }

    private func run() async {
        guard recipe.installer != nil else {
            fail("Recipe has no installer configured.")
            return
        }

        phase = .creatingBottle
        statusDetail = "Creating a new bottle…"
        progress = nil

        let url = bottleVM.createNewBottle(
            bottleName: recipe.title,
            winVersion: .win10,
            bottleURL: BottleData.defaultBottleDir
        )
        bottleURL = url

        let bottle = await waitForBottle(url: url)
        if Task.isCancelled { return }
        guard let bottle else {
            fail("Bottle creation failed or timed out. Check that Wine is installed and try again.")
            return
        }

        phase = .configuringBottle
        statusDetail = "Waiting for Wine prefix…"
        let windowsDir = bottle.url.appending(path: "drive_c").appending(path: "windows")
        let windowsReady = await waitForPath(windowsDir, timeout: 45)
        if Task.isCancelled { return }
        if !windowsReady {
            Logger.wineKit.warning("GameInstaller: drive_c/windows not found after timeout")
        }

        statusDetail = "Applying recipe settings…"
        await applyRecipeSettings(to: bottle)
        if Task.isCancelled { return }

        switch recipe.installer {
        case .steam:
            await runSteamInstaller(bottle: bottle)
        case .gog, .custom, .none:
            await runPickedInstaller(bottle: bottle)
        }
    }

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
            statusDetail = "Installed."
            progress = nil
            NotificationCenter.default.post(name: .macbottleInstalledGamesChanged, object: nil)
        } catch {
            fail("Could not save install record: \(error.localizedDescription)")
        }
    }

    private static let steamSetupURL: URL = {
        guard let url = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe") else {
            preconditionFailure("static Steam setup URL")
        }
        return url
    }()

    private func runSteamInstaller(bottle: Bottle) async {
        phase = .configuringBottle
        statusDetail = "Preparing Wine for Steam…"
        progress = nil
        await prepareWineForSteam(bottle: bottle)
        if Task.isCancelled { return }

        phase = .nativeSeedingSteam
        statusDetail = "Native Download Bridge: seeding Windows Steam client at macOS speed…"
        progress = 0

        do {
            let result = try await DownloadBridge.seedSteamClient(bottleURL: bottle.url) { prog, detail in
                Task { @MainActor in
                    self.progress = prog.fraction
                    self.statusDetail = detail
                }
            }
            statusDetail = "Seeded Steam \(result.version) · \(result.packageCount) packages · \(Self.formatBytes(result.totalBytes)) via native CDN"
            progress = 1
        } catch {
            Logger.wineKit.error("Native seed failed, falling back to SteamSetup: \(error.localizedDescription)")
            statusDetail = "Native seed failed (\(error.localizedDescription)). Falling back to SteamSetup…"
            if Task.isCancelled { return }
            await runSteamSetupFallback(bottle: bottle)
            return
        }
        if Task.isCancelled { return }

        if let appID = SteamAppID.parse(fromRecipeID: recipe.id) {
            let credentials = pendingCredentials ?? .anonymous
            phase = .downloadingDepot
            progress = 0
            statusDetail = "Native steamcmd: app_update \(appID) (windows platform)…"
            do {
                try await DownloadBridge.downloadGameDepot(
                    appID: appID,
                    credentials: credentials,
                    intoBottle: bottle.url
                ) { prog in
                    Task { @MainActor in
                        self.progress = prog.fraction
                        self.statusDetail = prog.detail
                        if prog.detail.lowercased().contains("clone")
                            || prog.detail.lowercased().contains("material") {
                            self.phase = .materializingDepot
                        } else {
                            self.phase = .downloadingDepot
                        }
                    }
                }
                phase = .materializingDepot
                progress = 1
                statusDetail = "Depot ready — launching Steam control plane…"
            } catch is CancellationError {
                return
            } catch SteamCMDError.needsSteamGuard {
                fail("Steam Guard code required. Enter the code and install again.")
                return
            } catch {
                Logger.wineKit.error("Depot download failed: \(error.localizedDescription)")
                statusDetail = "Native depot download failed (\(error.localizedDescription)). You can still install via Steam UI."
            }
        }
        if Task.isCancelled { return }

        phase = .runningInstaller
        progress = nil
        statusDetail = "Launching Steam (control plane only)…"

        let steamExe = bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "Steam.exe")
        let steamExeAlt = steamExe.deletingLastPathComponent().appending(path: "steam.exe")
        let launchURL = FileManager.default.fileExists(atPath: steamExe.path) ? steamExe : steamExeAlt

        var launchArgs: [String] = []
        if let appID = SteamAppID.parse(fromRecipeID: recipe.id) {
            launchArgs = ["-applaunch", String(appID)]
        }

        Task.detached(priority: .userInitiated) {
            do {
                try await Wine.runProgram(
                    at: launchURL,
                    args: launchArgs,
                    bottle: bottle,
                    environment: ["WINEDEBUG": "-all"],
                    autoSelectEngine: false
                )
            } catch {
                Logger.wineKit.error(
                    "GameInstaller: Steam process ended with error: \(error.localizedDescription)"
                )
            }
        }

        if SteamAppID.parse(fromRecipeID: recipe.id) != nil {
            statusDetail = """
            Game depot was downloaded at native speed via steamcmd and cloned into the bottle. Steam is only the control plane (DRM / launch). If the game does not auto-start, open Library in Steam, then continue and pick the main .exe.
            """
        } else {
            statusDetail = """
            Steam client was seeded natively. Log in, install the game, then continue.
            """
        }
    }

    private func runSteamSetupFallback(bottle: Bottle) async {
        phase = .downloadingSteamSetup
        statusDetail = "Connecting to Steam CDN…"
        progress = 0

        let tempSetup: URL
        do {
            tempSetup = try await downloadSteamSetup()
        } catch {
            if Task.isCancelled { return }
            fail("Could not download SteamSetup.exe: \(error.localizedDescription)")
            return
        }
        if Task.isCancelled { return }

        phase = .runningInstaller
        statusDetail = "Launching Steam installer (fallback)…"
        progress = nil

        let setupURL = tempSetup
        Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: setupURL) }
            do {
                try await Wine.runProgram(
                    at: setupURL,
                    bottle: bottle,
                    environment: ["WINEDEBUG": "-all"],
                    autoSelectEngine: false
                )
            } catch {
                Logger.wineKit.error(
                    "GameInstaller: Steam installer process ended with error: \(error.localizedDescription)"
                )
            }
        }

        statusDetail = "SteamSetup fallback launched. Finish setup in the Steam window, then continue."
    }

    private func prepareWineForSteam(bottle: Bottle) async {
        let reg = """
        REGEDIT4

        [HKEY_CURRENT_USER\\Software\\Wine\\WineDbg]
        "ShowCrashDialog"=dword:00000000
        """
        let regURL = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-steam-prep-\(UUID().uuidString).reg")
        do {
            try reg.write(to: regURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: regURL) }
            try await Wine.runWine(
                ["regedit", "/s", regURL.path(percentEncoded: false)],
                bottle: bottle,
                environment: ["WINEDEBUG": "-all"]
            )
        } catch {
            Logger.wineKit.debug("GameInstaller: steam prep failed: \(error.localizedDescription)")
        }
    }

    private func downloadSteamSetup() async throws -> URL {
        let downloader = SteamSetupDownloader()
        downloader.onProgress = { [weak self] written, expected in
            Task { @MainActor in
                guard let self else { return }
                if expected > 0 {
                    self.progress = min(1, Double(written) / Double(expected))
                    self.statusDetail = "Downloading SteamSetup.exe… \(Self.formatBytes(written)) / \(Self.formatBytes(expected))"
                } else {
                    self.progress = nil
                    self.statusDetail = "Downloading SteamSetup.exe… \(Self.formatBytes(written))"
                }
            }
        }
        let url = try await downloader.download(from: Self.steamSetupURL)
        progress = 1
        statusDetail = "Download complete."
        return url
    }

    private func runPickedInstaller(bottle: Bottle) async {
        statusDetail = "Select the Windows installer…"
        progress = nil
        let picked = await pickInstallerExe()
        guard let picked else {
            fail("Installer selection cancelled.")
            return
        }

        phase = .runningInstaller
        statusDetail = "Launching installer…"

        let installerURL = picked
        Task.detached(priority: .userInitiated) {
            do {
                try await Wine.runProgram(at: installerURL, bottle: bottle, autoSelectEngine: false)
            } catch {
                Logger.wineKit.error(
                    "GameInstaller: installer process ended with error: \(error.localizedDescription)"
                )
            }
        }

        statusDetail = "Installer launched. Complete installation in the window that opened, then continue."
    }

    @MainActor
    private func pickInstallerExe() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.exe, UTType(exportedAs: "com.microsoft.msi-installer")]
        panel.prompt = "Select installer"
        panel.message = "Choose the Windows installer for \(recipe.title)."
        let response = await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }
        guard response == .OK else { return nil }
        return panel.url
    }

    private func applyRecipeSettings(to bottle: Bottle) async {
        bottle.settings.dxvk = (recipe.renderer == .dxvk)

        statusDetail = "Installing CJK fonts…"
        await installCJKFontSubstitutions(bottle: bottle)

        Logger.wineKit.info("GameInstaller: applied recipe \(self.recipe.id) to bottle \(bottle.url.lastPathComponent)")
    }

    private func installCJKFontSubstitutions(bottle: Bottle) async {
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

        let substitutions: [(String, String)] = [
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

        var reg = "REGEDIT4\n\n[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]\n"
        for (windows, replacement) in substitutions {
            reg += "\"\(windows)\"=\"\(replacement)\"\n"
        }
        reg += "\n[HKEY_CURRENT_USER\\Software\\Wine\\Fonts]\n"
        reg += "\"WenQuanYi Micro Hei\"=\"wqy-microhei.ttc\"\n"

        let regURL = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-fonts-\(UUID().uuidString).reg")
        do {
            try reg.write(to: regURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: regURL) }
            statusDetail = "Registering font substitutions…"
            try await Wine.runWine(
                ["regedit", "/s", regURL.path(percentEncoded: false)],
                bottle: bottle
            )
        } catch {
            Logger.wineKit.debug("GameInstaller: font registration failed: \(error.localizedDescription)")
        }
    }

    private func waitForBottle(url: URL, timeout: TimeInterval = 180) async -> Bottle? {
        let deadline = Date().addingTimeInterval(timeout)
        var sawInFlight = false
        var ticks = 0
        while Date() < deadline {
            if Task.isCancelled { return nil }
            if let bottle = bottleVM.bottles.first(where: { $0.url == url }) {
                if bottle.inFlight {
                    sawInFlight = true
                    ticks += 1
                    if ticks % 4 == 0 {
                        statusDetail = "Initializing Wine prefix… (\(ticks / 4)s)"
                    }
                } else {
                    return bottle
                }
            } else if sawInFlight {
                return nil
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private func waitForPath(_ url: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func wineStylePath(for fileURL: URL, inBottle bottle: Bottle) -> String {
        let driveC = bottle.url.appending(path: "drive_c").path
        let full = fileURL.path
        if full.hasPrefix(driveC) {
            let relative = String(full.dropFirst(driveC.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "C:\\" + relative.replacingOccurrences(of: "/", with: "\\")
        }
        return full.replacingOccurrences(of: "/", with: "\\")
    }

    private func fail(_ message: String) {
        phase = .failed(message: message)
        statusDetail = message
        progress = nil
    }

    private static func formatBytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }
}

private final class SteamSetupDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: ((Int64, Int64) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var destinationURL: URL?

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = FileManager.default.temporaryDirectory
            .appending(path: "SteamSetup-\(UUID().uuidString).exe")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: location, to: dest)
            destinationURL = dest
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
        }
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }
        if let destinationURL {
            continuation?.resume(returning: destinationURL)
        } else {
            continuation?.resume(throwing: URLError(.cannotCreateFile))
        }
        continuation = nil
    }
}

extension Notification.Name {
    static let macbottleInstalledGamesChanged = Notification.Name("app.macbottle.installedGamesChanged")
}
