//
//  WhiskyApp.swift
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
import Sparkle
import WhiskyKit
import os.log

@main
struct WhiskyApp: App {
    @State var showSetup: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL
    private let updaterController: SPUStandardUpdaterController

    init() {
        // MacBottle: keep Sparkle wired in so we can re-enable it once
        // we have a real appcast and EdDSA key pair, but do not start
        // the updater at launch. A running updater with an unconfigured
        // feed/public key causes "Unable to Check For Updates" dialogs
        // during development. Re-enable by flipping the flag back to
        // true once `SUFeedURL` and `SUPublicEDKey` in Info.plist are
        // populated with real values.
        updaterController = SPUStandardUpdaterController(startingUpdater: false,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showSetup: $showSetup)
                .frame(minWidth: ViewWidth.large, minHeight: 316)
                .environment(BottleVM.shared)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false

                    Task.detached {
                        await WhiskyApp.deleteOldLogs()
                    }
                }
        }
        // Don't ask me how this works, it just does
        .handlesExternalEvents(matching: ["{same path of URL?}"])
        .commands {
            // MacBottle: "Check for Updates…" menu entry is removed
            // until a real appcast and EdDSA key pair are provisioned.
            // See `init()` above for the matching `startingUpdater:
            // false` flag. Re-add once releases ship.
            CommandGroup(before: .systemServices) {
                Divider()
                Button("open.setup") {
                    showSetup = true
                }
                Button("install.cli") {
                    Task {
                        await WhiskyCmd.install()
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("open.bottle") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.urls.first {
                                BottleVM.shared.bottlesList.paths.append(url)
                                BottleVM.shared.loadBottles()
                            }
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: [.command])
            }
            CommandGroup(after: .importExport) {
                Button("open.logs") {
                    WhiskyApp.openLogsFolder()
                }
                .keyboardShortcut("L", modifiers: [.command])
                Button("kill.bottles") {
                    WhiskyApp.killBottles()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                Button("wine.clearShaderCaches") {
                    WhiskyApp.killBottles() // Better not make things more complicated for ourselves
                    WhiskyApp.wipeShaderCaches()
                }
            }
            CommandGroup(replacing: .help) {
                Button("help.website") {
                    if let url = URL(string: "https://getwhisky.app/") {
                        openURL(url)
                    }
                }
                Button("help.github") {
                    if let url = URL(string: "https://github.com/Whisky-App/Whisky") {
                        openURL(url)
                    }
                }
                Button("help.discord") {
                    if let url = URL(string: "https://discord.gg/CsqAfs9CnM") {
                        openURL(url)
                    }
                }
            }
        }
        Settings {
            SettingsView()
        }
    }

    static func killBottles() {
        let bottles = BottleVM.shared.bottles
        Task {
            await withTaskGroup(of: Void.self) { group in
                for bottle in bottles {
                    group.addTask {
                        do {
                            try await Wine.killBottle(bottle: bottle)
                        } catch {
                            Logger.app.error("Failed to kill bottle: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    static func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
    }

    static func deleteOldLogs() {
        let pastDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let logs = urls.filter { url in
            url.pathExtension == "log"
        }

        let oldLogs = logs.filter { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])

                return resourceValues.creationDate ?? Date() < pastDate
            } catch {
                return false
            }
        }

        for log in oldLogs {
            do {
                try FileManager.default.removeItem(at: log)
            } catch {
                Logger.app.error("Failed to delete log: \(error.localizedDescription)")
            }
        }
    }

    static func wipeShaderCaches() {
        let getconf = Process()
        getconf.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        getconf.arguments = ["DARWIN_USER_CACHE_DIR"]
        let pipe = Pipe()
        getconf.standardOutput = pipe
        do {
            try getconf.run()
            getconf.waitUntilExit()
            let getconfOutput = try pipe.fileHandleForReading.readToEnd() ?? Data()
            guard let getconfOutputString = String(data: getconfOutput, encoding: .utf8) else { return }
            let d3dmPath = URL(fileURLWithPath: getconfOutputString.trimmingCharacters(in: .whitespacesAndNewlines))
                .appending(path: "d3dm")
            try? FileManager.default.removeItem(at: d3dmPath)
        } catch {
            return
        }
    }
}
