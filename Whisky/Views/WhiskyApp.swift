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
import WhiskyKit
import os.log

@main
struct WhiskyApp: App {
    @State var showSetup: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL
    @AppStorage("checkAppUpdates") var checkAppUpdates = true

    var body: some Scene {
        WindowGroup {
            ContentView(showSetup: $showSetup)
                .frame(minWidth: 860, idealWidth: 1180, minHeight: 560, idealHeight: 720)
                .environment(BottleVM.shared)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false

                    Task.detached {
                        await WhiskyApp.deleteOldLogs()
                    }

                    if checkAppUpdates {
                        Task {
                            await WhiskyApp.checkForAppUpdates(userInitiated: false)
                        }
                    }
                }
        }
        .defaultSize(width: 1180, height: 720)
        // Don't ask me how this works, it just does
        .handlesExternalEvents(matching: ["{same path of URL?}"])
        .commands {
            CommandGroup(after: .appInfo) {
                Button("check.updates") {
                    Task {
                        await WhiskyApp.checkForAppUpdates(userInitiated: true)
                    }
                }
            }
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
                Button("button.createBottle") {
                    NotificationCenter.default.post(name: .macbottleNewBottle, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
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
                    if let url = URL(string: "https://github.com/shiaho777/MacBottle") {
                        openURL(url)
                    }
                }
                Button("help.github") {
                    if let url = URL(string: "https://github.com/shiaho777/MacBottle") {
                        openURL(url)
                    }
                }
            }
        }
        Settings {
            SettingsView()
        }
    }

    static func killBottles(force: Bool = true) {
        let bottles = BottleVM.shared.bottles
        if force {
            BottleForceStop.forceStopAllBottles(bottles: bottles)
            return
        }
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

    @MainActor
    static func checkForAppUpdates(userInitiated: Bool) async {
        guard let current = AppUpdateChecker.currentVersion() else { return }
        let currentText = "\(current.major).\(current.minor).\(current.patch)"
        let alert = NSAlert()
        do {
            let status = try await AppUpdateChecker().check(currentVersion: current)
            switch status {
            case .available(let release):
                alert.messageText = String(localized: "update.app.available.title")
                alert.informativeText = String(
                    localized: "update.app.available.message \(release.tagName) \(currentText)"
                )
                alert.addButton(withTitle: String(localized: "update.app.download"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(release.pageURL)
                }
                return
            case .upToDate:
                guard userInitiated else { return }
                alert.messageText = String(localized: "update.app.upToDate.title")
                alert.informativeText = String(localized: "update.app.upToDate.message \(currentText)")
            case .noPublishedRelease:
                guard userInitiated else { return }
                alert.messageText = String(localized: "update.app.noRelease.title")
                alert.informativeText = String(localized: "update.app.noRelease.message")
            }
        } catch {
            Logger.app.info("App update check failed: \(error.localizedDescription)")
            guard userInitiated else { return }
            alert.messageText = String(localized: "update.app.failed.title")
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
