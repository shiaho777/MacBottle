//
//  BottleVM.swift
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
import SemanticVersion
import WhiskyKit
import os.log

@Observable
final class BottleVM: @unchecked Sendable {
    @MainActor static let shared = BottleVM()

    var bottlesList = BottleData()
    var bottles: [Bottle] = []

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task.detached {
            var bottleId: Bottle?
            do {
                guard WhiskyWineInstaller.isWhiskyWineInstalled() else {
                    throw BottleCreationError.wineNotInstalled
                }
                guard FileManager.default.fileExists(atPath: Wine.wineBinary.path(percentEncoded: false)) else {
                    throw BottleCreationError.wineBinaryMissing(Wine.wineBinary.path(percentEncoded: false))
                }

                try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle

                await MainActor.run {
                    self.bottles.append(bottle)
                }

                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)
                await MainActor.run {
                    self.bottlesList.paths.append(newBottleDir)
                    self.loadBottles()
                }
            } catch {
                Logger.app.error("Failed to create new bottle: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: newBottleDir)
                if let bottle = bottleId {
                    await MainActor.run {
                        if let index = self.bottles.firstIndex(of: bottle) {
                            self.bottles.remove(at: index)
                        }
                    }
                }
                await MainActor.run {
                    Self.presentCreationError(error)
                }
            }
        }
        return newBottleDir
    }

    @MainActor
    private static func presentCreationError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to create bottle"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum BottleCreationError: LocalizedError {
    case wineNotInstalled
    case wineBinaryMissing(String)

    var errorDescription: String? {
        switch self {
        case .wineNotInstalled:
            return "WhiskyWine is not installed. Open Setup from the Whisky menu and install Wine first."
        case .wineBinaryMissing(let path):
            return "Wine binary not found at \(path)."
        }
    }
}
