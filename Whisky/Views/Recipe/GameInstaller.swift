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
            fail(String(localized: "game.install.cancelled"))
        }
    }

    func markInstallerFinished() {
        guard let url = bottleURL else { return }
        phase = .awaitingMainExe(bottleURL: url)
        statusDetail = String(localized: "game.install.pickMainExe")
        progress = nil
    }

    private func run() async {
        guard recipe.installer != nil else {
            fail(String(localized: "game.install.error.noInstaller"))
            return
        }

        phase = .creatingBottle
        statusDetail = String(localized: "game.install.creatingBottle")
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
            fail(String(localized: "game.install.error.bottleTimeout"))
            return
        }

        phase = .configuringBottle
        statusDetail = String(localized: "game.install.waitingPrefix")
        let windowsDir = bottle.url.appending(path: "drive_c").appending(path: "windows")
        let windowsReady = await waitForPath(windowsDir, timeout: 45)
        if Task.isCancelled { return }
        if !windowsReady {
            Logger.wineKit.warning("GameInstaller: drive_c/windows not found after timeout")
        }

        statusDetail = String(localized: "game.install.applyingRecipe")
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
            statusDetail = String(localized: "game.install.done")
            progress = nil
            NotificationCenter.default.post(name: .macbottleInstalledGamesChanged, object: nil)
        } catch {
            fail(String(format: String(localized: "game.install.error.saveRecord %@"), error.localizedDescription))
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
        statusDetail = String(localized: "game.install.preparingWine")
        progress = nil
        await prepareWineForSteam(bottle: bottle)
        if Task.isCancelled { return }

        phase = .nativeSeedingSteam
        statusDetail = String(localized: "game.install.seedingSteam")
        progress = 0

        do {
            let result = try await DownloadBridge.seedSteamClient(bottleURL: bottle.url) { prog, detail in
                Task { @MainActor in
                    self.progress = prog.fraction
                    self.statusDetail = detail
                }
            }
            statusDetail = String(
                format: String(localized: "game.install.seeded %@ %@ %@"),
                result.version,
                String(result.packageCount),
                Self.formatBytes(result.totalBytes)
            )
            progress = 1
        } catch {
            Logger.wineKit.error("Native seed failed, falling back to SteamSetup: \(error.localizedDescription)")
            statusDetail = String(
                format: String(localized: "game.install.seedFailed %@"),
                error.localizedDescription
            )
            if Task.isCancelled { return }
            await runSteamSetupFallback(bottle: bottle)
            return
        }
        if Task.isCancelled { return }

        if let appID = SteamAppID.parse(fromRecipeID: recipe.id) {
            let credentials = pendingCredentials ?? .anonymous
            phase = .downloadingDepot
            progress = 0
            statusDetail = String(
                format: String(localized: "game.install.depotUpdate %@"),
                String(appID)
            )
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
                statusDetail = String(localized: "game.install.depotReady")
            } catch is CancellationError {
                return
            } catch SteamCMDError.needsSteamGuard {
                fail(String(localized: "game.install.error.needsGuard"))
                return
            } catch {
                Logger.wineKit.error("Depot download failed: \(error.localizedDescription)")
                statusDetail = String(
                    format: String(localized: "game.install.error.depotFailed %@"),
                    error.localizedDescription
                )
            }
        }
        if Task.isCancelled { return }

        phase = .runningInstaller
        progress = nil
        statusDetail = String(localized: "game.install.launchingSteamControlPlane")

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
            statusDetail = String(localized: "game.install.steamControlPlaneNote")
        } else {
            statusDetail = String(localized: "game.install.steamSeededNote")
        }
    }

    private func runSteamSetupFallback(bottle: Bottle) async {
        phase = .downloadingSteamSetup
        statusDetail = String(localized: "game.install.connectingCDN")
        progress = 0

        let tempSetup: URL
        do {
            tempSetup = try await downloadSteamSetup()
        } catch {
            if Task.isCancelled { return }
            fail(String(
                format: String(localized: "game.install.error.setupDownloadFailed %@"),
                error.localizedDescription
            ))
            return
        }
        if Task.isCancelled { return }

        phase = .runningInstaller
        statusDetail = String(localized: "game.install.launchingSetupFallback")
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

        statusDetail = String(localized: "game.install.setupFallbackLaunched")
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
                    self.statusDetail = String(
                        format: String(localized: "game.install.downloadingSetupBytes %@ %@"),
                        Self.formatBytes(written),
                        Self.formatBytes(expected)
                    )
                } else {
                    self.progress = nil
                    self.statusDetail = String(
                        format: String(localized: "game.install.downloadingSetup %@"),
                        Self.formatBytes(written)
                    )
                }
            }
        }
        let url = try await downloader.download(from: Self.steamSetupURL)
        progress = 1
        statusDetail = String(localized: "game.install.downloadComplete")
        return url
    }

    private func runPickedInstaller(bottle: Bottle) async {
        statusDetail = String(localized: "game.install.selectInstallerPrompt")
        progress = nil
        let picked = await pickInstallerExe()
        guard let picked else {
            fail(String(localized: "game.install.error.selectionCancelled"))
            return
        }

        phase = .runningInstaller
        statusDetail = String(localized: "game.install.launchingInstaller")

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

        statusDetail = String(localized: "game.install.installerLaunched")
    }

    @MainActor
    private func pickInstallerExe() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.exe, UTType(exportedAs: "com.microsoft.msi-installer")]
        panel.prompt = String(localized: "game.install.panel.prompt")
        panel.message = String(
            format: String(localized: "game.install.panel.message %@"),
            recipe.title
        )
        typealias ModalContinuation = CheckedContinuation<NSApplication.ModalResponse, Never>
        let response = await withCheckedContinuation { (continuation: ModalContinuation) in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }
        guard response == .OK else { return nil }
        return panel.url
    }

    private func applyRecipeSettings(to bottle: Bottle) async {
        bottle.settings.dxvk = (recipe.renderer == .dxvk)

        statusDetail = String(localized: "game.install.installingCJKFonts")
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
            statusDetail = String(localized: "game.install.registeringFonts")
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
                        statusDetail = String(
                        format: String(localized: "game.install.initializingPrefix %@"),
                        String(ticks / 4)
                    )
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
