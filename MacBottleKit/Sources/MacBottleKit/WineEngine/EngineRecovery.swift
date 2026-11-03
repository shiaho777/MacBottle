//
//  EngineRecovery.swift
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

/// Finds a Wine engine that already exists on this Mac, so a fresh
/// install does not depend on the archived upstream feed.
///
/// Candidates are the same ones `WineEngineCatalog` uses for the
/// D3DMetal bridge: a `Libraries.bak*` folder under the current bundle id
/// and the legacy `com.isaacmarovitz.Whisky` install.
public enum EngineRecovery {
    public static func legacyEngineRoot() -> URL? {
        WineEngineCatalog.preferredBackupLibraries()
    }

    public static func canRecover() -> Bool {
        guard legacyEngineRoot() != nil else { return false }
        return !CrossOverEngine.default.isInstalled()
    }
}
