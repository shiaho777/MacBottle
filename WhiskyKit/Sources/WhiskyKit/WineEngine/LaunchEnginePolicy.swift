//
//  LaunchEnginePolicy.swift
//  WhiskyKit
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
import os.log

public enum LaunchEnginePolicy {
    public static let autoSelectDefaultsKey = "macbottle.autoSelectEngine"
    public static let autoEngineToken = "auto"

    public static var autoSelectEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoSelectDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoSelectDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoSelectDefaultsKey)
        }
    }

    public struct Decision: Sendable, Equatable {
        public let engineID: String
        public let reason: String
        public let importProfile: PEImportProfile?
        public let recipeRenderer: RecipeRenderer?
        public let bottlePinned: Bool
    }

    public static func decide(
        executable: URL,
        recipe: Recipe?,
        bottleDXVKEnabled: Bool,
        bottleEngineID: String? = nil
    ) -> Decision {
        let importProfile = PEImportScanner.scan(url: executable)
        let runtimeProfile = RuntimeLaunchOptimizer.profile(forExecutableAt: executable)

        if let pinned = normalizedBottleEngineID(bottleEngineID) {
            if pinned == WineEngineCatalog.d3dMetalIdentifier {
                if canUseD3DMetalEngine() || canInstallD3DMetalEngine() {
                    return Decision(
                        engineID: pinned,
                        reason: "bottle.engine=d3dmetal",
                        importProfile: importProfile,
                        recipeRenderer: recipe?.renderer,
                        bottlePinned: true
                    )
                }
                return Decision(
                    engineID: WineEngineCatalog.modernIdentifier,
                    reason: "bottle.engine=d3dmetal unavailable → modern",
                    importProfile: importProfile,
                    recipeRenderer: recipe?.renderer,
                    bottlePinned: true
                )
            }
            return Decision(
                engineID: pinned,
                reason: "bottle.engine=\(pinned)",
                importProfile: importProfile,
                recipeRenderer: recipe?.renderer,
                bottlePinned: true
            )
        }

        if let recipe {
            switch recipe.renderer {
            case .d3dmetal:
                if canUseD3DMetalEngine() {
                    return Decision(
                        engineID: WineEngineCatalog.d3dMetalIdentifier,
                        reason: "recipe.renderer=d3dmetal",
                        importProfile: importProfile,
                        recipeRenderer: recipe.renderer,
                        bottlePinned: false
                    )
                }
                return Decision(
                    engineID: WineEngineCatalog.modernIdentifier,
                    reason: "recipe.d3dmetal fallback modern (engine missing)",
                    importProfile: importProfile,
                    recipeRenderer: recipe.renderer,
                    bottlePinned: false
                )
            case .dxvk:
                return Decision(
                    engineID: WineEngineCatalog.modernIdentifier,
                    reason: "recipe.renderer=dxvk",
                    importProfile: importProfile,
                    recipeRenderer: recipe.renderer,
                    bottlePinned: false
                )
            case .wined3d:
                return Decision(
                    engineID: WineEngineCatalog.modernIdentifier,
                    reason: "recipe.renderer=wined3d",
                    importProfile: importProfile,
                    recipeRenderer: recipe.renderer,
                    bottlePinned: false
                )
            }
        }

        if runtimeProfile == .classic32 || importProfile?.architecture == .x32 {
            return Decision(
                engineID: WineEngineCatalog.modernIdentifier,
                reason: "classic32",
                importProfile: importProfile,
                recipeRenderer: nil,
                bottlePinned: false
            )
        }

        if let importProfile {
            switch importProfile.preferredRenderer {
            case .d3dmetal:
                if canUseD3DMetalEngine() || canInstallD3DMetalEngine() {
                    return Decision(
                        engineID: WineEngineCatalog.d3dMetalIdentifier,
                        reason: "pe.\(importProfile.primaryGraphicsAPI.rawValue)",
                        importProfile: importProfile,
                        recipeRenderer: nil,
                        bottlePinned: false
                    )
                }
                return Decision(
                    engineID: WineEngineCatalog.modernIdentifier,
                    reason: "pe.d3dmetal unavailable → modern",
                    importProfile: importProfile,
                    recipeRenderer: nil,
                    bottlePinned: false
                )
            case .dxvk:
                return Decision(
                    engineID: WineEngineCatalog.modernIdentifier,
                    reason: "pe.vulkan/d3d10 → modern+dxvk path",
                    importProfile: importProfile,
                    recipeRenderer: nil,
                    bottlePinned: false
                )
            case .wined3d:
                return Decision(
                    engineID: WineEngineCatalog.modernIdentifier,
                    reason: "pe.legacy-graphics",
                    importProfile: importProfile,
                    recipeRenderer: nil,
                    bottlePinned: false
                )
            }
        }

        if bottleDXVKEnabled {
            return Decision(
                engineID: WineEngineCatalog.modernIdentifier,
                reason: "bottle.dxvk",
                importProfile: importProfile,
                recipeRenderer: nil,
                bottlePinned: false
            )
        }

        return Decision(
            engineID: WineEngineRegistry.shared.current.identifier,
            reason: "keep-current",
            importProfile: importProfile,
            recipeRenderer: nil,
            bottlePinned: false
        )
    }

    @discardableResult
    public static func applyForLaunch(
        executable: URL,
        recipe: Recipe?,
        bottleDXVKEnabled: Bool,
        bottleEngineID: String? = nil
    ) -> Decision {
        let decision = decide(
            executable: executable,
            recipe: recipe,
            bottleDXVKEnabled: bottleDXVKEnabled,
            bottleEngineID: bottleEngineID
        )

        let shouldApply: Bool
        if decision.bottlePinned {
            shouldApply = true
        } else {
            shouldApply = autoSelectEnabled
        }

        guard shouldApply else {
            Logger.wineKit.info(
                "LaunchEnginePolicy auto-select off; keep \(WineEngineRegistry.shared.current.identifier)"
            )
            return decision
        }

        if decision.engineID == WineEngineRegistry.shared.current.identifier {
            return decision
        }

        do {
            if decision.engineID == WineEngineCatalog.d3dMetalIdentifier {
                _ = try WineEngineCatalog.ensureD3DMetalEngine()
            }
            guard let engine = WineEngineCatalog.engine(id: decision.engineID),
                  engine.isInstalled() else {
                return decision
            }
            WineEngineRegistry.shared.setCurrent(engine, persist: false)
            Logger.wineKit.info(
                "LaunchEnginePolicy temporary engine \(decision.engineID) (\(decision.reason))"
            )
        } catch {
            Logger.wineKit.error(
                "LaunchEnginePolicy failed to select \(decision.engineID): \(error.localizedDescription)"
            )
        }
        return decision
    }

    public static func restoreUserSelection() {
        if let id = UserDefaults.standard.string(forKey: WineEngineRegistry.selectionDefaultsKey),
           let engine = WineEngineCatalog.engine(id: id),
           engine.isInstalled() {
            WineEngineRegistry.shared.setCurrent(engine, persist: false)
            return
        }
        WineEngineRegistry.shared.setCurrent(CrossOverEngine.default, persist: false)
    }

    public static func normalizedBottleEngineID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != autoEngineToken else { return nil }
        if WineEngineCatalog.engine(id: trimmed) != nil {
            return trimmed
        }
        return nil
    }

    private static func canUseD3DMetalEngine() -> Bool {
        let engine = WineEngineCatalog.d3dMetalEngine()
        return engine.isInstalled() && engine.supportsD3DMetalBridge
    }

    private static func canInstallD3DMetalEngine() -> Bool {
        WineEngineCatalog.preferredBackupLibraries() != nil
            || WineEngineCatalog.d3dMetalEngine().isInstalled()
    }
}
