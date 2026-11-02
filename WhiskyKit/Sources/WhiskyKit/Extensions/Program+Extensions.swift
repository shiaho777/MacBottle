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
        let arguments = ShellArgumentParser.parse(settings.arguments)
        let environment = generateEnvironment()
        let launchMode = settings.launchMode
        let launchCommandArgs = ShellArgumentParser.parse(settings.launchCommand)
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
                ProgramLaunchCoordinator.shared.noteAlreadyLaunching(programName: programName)
                return
            }

            let bottleName = bottle.settings.name
            Task.detached(priority: .userInitiated) {
                do {
                    if let recipe {
                        // Side-effectful recipe fields (winetricks,
                        // registry) are applied once per bottle-recipe
                        // pairing, not on every launch.
                        let plan = RecipeProvisioningPlan(recipe: recipe)
                        if !plan.isEmpty {
                            await MainActor.run {
                                ProgramLaunchCoordinator.shared.beginProvisioning(
                                    programName: programName,
                                    bottleName: bottleName,
                                    detail: String(localized: "game.install.applyingRecipe")
                                )
                            }
                            try await RecipeProvisioner.shared.provisionIfNeeded(
                                recipe: recipe,
                                bottle: bottle
                            ) { detail in
                                Task { @MainActor in
                                    ProgramLaunchCoordinator.shared.updateProvisioning(detail: detail)
                                }
                            }
                            await MainActor.run {
                                ProgramLaunchCoordinator.shared.endProvisioning(
                                    programName: programName,
                                    bottleName: bottleName
                                )
                            }
                        }
                    }
                    switch launchMode {
                    case .file:
                        try await Wine.runProgram(
                            at: programURL,
                            args: arguments,
                            bottle: bottle,
                            environment: environment,
                            wait: false,
                            recipe: recipe,
                            autoSelectEngine: true
                        )
                    case .command:
                        try await Wine.runWine(
                            launchCommandArgs,
                            bottle: bottle,
                            environment: environment
                        )
                    }
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
