//
//  WhiskyWineInstaller.swift
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
import SemanticVersion

/// MacBottle: kept as a thin compatibility layer.
///
/// The real logic moved to `CrossOverEngine` and the process-wide
/// `WineEngineRegistry.shared.current`. Existing call sites continue to
/// reach the right files because every symbol on `WhiskyWineInstaller`
/// now forwards to the active engine. New code should use
/// `WineEngineRegistry.shared.current` directly so the chosen Wine flavour
/// is honoured once multiple engines ship.
public class WhiskyWineInstaller {
    private static var engine: any WineEngine {
        WineEngineRegistry.shared.current
    }

    public static var applicationFolder: URL {
        CrossOverEngine.applicationFolder
    }

    public static var libraryFolder: URL {
        engine.libraryRoot
    }

    public static var binFolder: URL {
        // Derive via the engine's `wineBinary` to keep a single source of
        // truth, even though CrossOverEngine also exposes `binFolder`.
        engine.wineBinary.deletingLastPathComponent()
    }

    public static func isWhiskyWineInstalled() -> Bool {
        engine.isInstalled()
    }

    public static func install(from: URL) {
        do {
            try engine.install(from: from)
        } catch {
            Logger.wineKit.error("Failed to install Wine engine: \(error.localizedDescription)")
        }
    }

    public static func uninstall() {
        do {
            try engine.uninstall()
        } catch {
            Logger.wineKit.error("Failed to uninstall Wine engine: \(error.localizedDescription)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let result = await engine.checkForUpdate()
        return (result.hasUpdate, result.remoteVersion)
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        engine.installedVersion()
    }
}

/// Version descriptor written by the Wine packaging pipeline as
/// `WhiskyWineVersion.plist`. Kept public so `CrossOverEngine` and any
/// historical callers can decode it.
public struct WhiskyWineVersion: Codable, Sendable {
    public var version: SemanticVersion

    public init(version: SemanticVersion = SemanticVersion(1, 0, 0)) {
        self.version = version
    }
}
