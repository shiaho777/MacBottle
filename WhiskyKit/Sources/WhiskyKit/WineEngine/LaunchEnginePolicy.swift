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

    /// What `applyForLaunch` decided and which engine the launch must
    /// actually run under. `engine` is resolved eagerly so the spawn
    /// path never has to re-read the mutable registry after an await
    /// point.
    public struct AppliedLaunch: Sendable {
        public let decision: Decision
        public let engine: any WineEngine
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
    ) -> AppliedLaunch {
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
            return AppliedLaunch(decision: decision, engine: WineEngineRegistry.shared.current)
        }

        if decision.engineID == WineEngineRegistry.shared.current.identifier {
            return AppliedLaunch(decision: decision, engine: WineEngineRegistry.shared.current)
        }

        do {
            if decision.engineID == WineEngineCatalog.d3dMetalIdentifier {
                _ = try WineEngineCatalog.ensureD3DMetalEngine()
            }
            guard let engine = WineEngineCatalog.engine(id: decision.engineID),
                  engine.isInstalled() else {
                let actual = WineEngineRegistry.shared.current
                Logger.wineKit.error(
                    // swiftlint:disable:next line_length
                    "LaunchEnginePolicy selected \(decision.engineID) but it is unavailable; running \(actual.identifier)"
                )
                return AppliedLaunch(
                    decision: Self.decision(decision, reportingActualEngineID: actual.identifier),
                    engine: actual
                )
            }
            WineEngineRegistry.shared.setCurrent(engine, persist: false)
            Logger.wineKit.info(
                "LaunchEnginePolicy temporary engine \(decision.engineID) (\(decision.reason))"
            )
            return AppliedLaunch(decision: decision, engine: engine)
        } catch {
            let actual = WineEngineRegistry.shared.current
            Logger.wineKit.error(
                "LaunchEnginePolicy failed to select \(decision.engineID): \(error.localizedDescription)"
            )
            return AppliedLaunch(
                decision: Self.decision(decision, reportingActualEngineID: actual.identifier),
                engine: actual
            )
        }
    }

    /// Rewrites a decision whose engine could not be applied so it names
    /// the engine that will actually run. Callers key behavior off the
    /// reported engine ID (e.g. disabling DXVK for d3dmetal), so a
    /// phantom ID would misconfigure the launch.
    static func decision(_ original: Decision, reportingActualEngineID actualID: String) -> Decision {
        guard original.engineID != actualID else { return original }
        return Decision(
            engineID: actualID,
            reason: "\(original.reason) (\(original.engineID) unavailable → \(actualID))",
            importProfile: original.importProfile,
            recipeRenderer: original.recipeRenderer,
            bottlePinned: original.bottlePinned
        )
    }

    /// Restores the user's saved selection. When `applied` is given, the
    /// restore only happens if the registry still holds what that launch
    /// applied — a concurrent launch or an explicit user choice wins.
    public static func restoreUserSelection(for applied: AppliedLaunch? = nil) {
        let target: any WineEngine
        if let id = UserDefaults.standard.string(forKey: WineEngineRegistry.selectionDefaultsKey),
           let engine = WineEngineCatalog.engine(id: id),
           engine.isInstalled() {
            target = engine
        } else {
            target = CrossOverEngine.default
        }
        if let applied {
            _ = WineEngineRegistry.shared.restoreIfCurrent(
                expectedIdentifier: applied.engine.identifier,
                engine: target
            )
        } else {
            WineEngineRegistry.shared.setCurrent(target, persist: false)
        }
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
