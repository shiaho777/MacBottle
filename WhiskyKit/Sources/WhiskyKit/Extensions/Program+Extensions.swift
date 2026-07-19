//
//  Program+Extensions.swift
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

extension Program {
    public func run() {
        markLaunched()
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            self.runInWine()
        }
    }

    func runInWine() {
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()
        let recipe: Recipe?
        if let recipeID = settings.recipeID {
            recipe = RecipeStore.shared.recipe(id: recipeID)
        } else {
            recipe = nil
        }
        let programName = name
        let programURL = url
        let bottle = bottle

        Task { @MainActor in
            guard ProgramLaunchCoordinator.shared.beginLaunch(
                programURL: programURL,
                programName: programName,
                bottle: bottle
            ) else {
                return
            }

            Task.detached(priority: .userInitiated) {
                do {
                    try await Wine.runProgram(
                        at: programURL,
                        args: arguments,
                        bottle: bottle,
                        environment: environment,
                        wait: false,
                        recipe: recipe,
                        autoSelectEngine: true
                    )
                    await MainActor.run {
                        ProgramLaunchCoordinator.shared.finishLaunchSuccess(
                            programURL: programURL,
                            programName: programName
                        )
                    }
                } catch {
                    await MainActor.run {
                        ProgramLaunchCoordinator.shared.finishLaunchFailure(
                            programURL: programURL,
                            programName: programName,
                            message: error.localizedDescription
                        )
                        self.showRunError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    public func generateTerminalCommand() -> String {
        return Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: settings.arguments, environment: generateEnvironment()
        )
    }

    public func runInTerminal() {
        let wineCmd = generateTerminalCommand()
        Task.detached(priority: .userInitiated) {
            do {
                try await TerminalLauncher.run(command: wineCmd)
            } catch {
                Logger.wineKit.error("Failed to run terminal command: \(error.localizedDescription)")
                await self.showRunError(message: error.localizedDescription)
            }
        }
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
