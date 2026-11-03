//
//  MacBottleCmd.swift
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
import os.log

class MacBottleCmd {
    static func install() async {
        guard let cliURL = Bundle.main.url(forResource: "MacBottleCmd", withExtension: nil) else {
            Logger.app.error("MacBottleCmd: CLI binary missing from the app bundle")
            return
        }

        let fileManager = FileManager.default
        let homebrew = "/opt/homebrew/bin"
        let intelHomebrew = "/usr/local/bin"

        if fileManager.fileExists(atPath: homebrew),
           fileManager.isWritableFile(atPath: homebrew) {
            installSymlink(cliURL, in: URL(fileURLWithPath: homebrew))
            return
        }
        if fileManager.fileExists(atPath: intelHomebrew),
           fileManager.isWritableFile(atPath: intelHomebrew) {
            installSymlink(cliURL, in: URL(fileURLWithPath: intelHomebrew))
            return
        }

        // No writable system prefix: install into the user's own bin
        // instead of asking for administrator privileges to write one
        // symlink into /usr/local/bin.
        let localBin = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".local/bin")
        do {
            try fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)
            installSymlink(cliURL, in: localBin)
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = String(localized: "alert.cli.installed.title")
                alert.informativeText = String(
                    format: String(localized: "alert.cli.installed.message %@"),
                    localBin.path(percentEncoded: false)
                )
                alert.alertStyle = .informational
                alert.addButton(withTitle: String(localized: "button.ok"))
                alert.runModal()
            }
        } catch {
            Logger.app.error("MacBottleCmd install error: \(error.localizedDescription)")
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = String(localized: "alert.message")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: String(localized: "button.ok"))
                alert.runModal()
            }
        }
    }

    private static func installSymlink(_ cliURL: URL, in directory: URL) {
        let link = directory.appending(path: "macbottle")
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: link.path(percentEncoded: false)) {
                try fileManager.removeItem(at: link)
            }
            try fileManager.createSymbolicLink(at: link, withDestinationURL: cliURL)
            Logger.app.info("MacBottleCmd installed at \(link.path, privacy: .public)")
        } catch {
            Logger.app.error("MacBottleCmd install error: \(error.localizedDescription)")
        }
    }
}
