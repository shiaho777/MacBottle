//
//  DisplayPolicy.swift
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

public enum DisplayPolicy {
    public static let macDriverKey = #"Software\\Wine\\Mac Driver"#
    public static let desktopKey = #"Control Panel\\Desktop"#

    @discardableResult
    public static func apply(for profile: RuntimeProfile, bottle: Bottle) async -> Bool {
        switch profile {
        case .classic32:
            return await applyClassic32(bottle: bottle)
        case .modern64, .installer, .generic:
            return false
        }
    }

    /// Classic 32-bit titles misrender under Retina scaling, so force
    /// RetinaMode=n and a sane DPI. Values are written through `wine reg`
    /// instead of editing `user.reg` directly: the launch path runs
    /// alongside a prewarmed (or still-live) wineserver that holds the
    /// registry in memory, and a plain file edit can be clobbered when
    /// that server flushes.
    @discardableResult
    public static func applyClassic32(bottle: Bottle) async -> Bool {
        var changed = false
        do {
            if try await Wine.retinaMode(bottle: bottle) {
                try await Wine.changeRetinaMode(bottle: bottle, retinaMode: false)
                changed = true
            }
            let currentDPI = try await Wine.dpiResolution(bottle: bottle)
            if currentDPI == nil || (currentDPI ?? 0) > 96 {
                try await Wine.changeDpiResolution(bottle: bottle, dpi: 96)
                changed = true
            }
            if changed {
                let bottleName = bottle.settings.name
                Logger.wineKit.info(
                    "DisplayPolicy: classic32 applied RetinaMode=n LogPixels<=96 for \(bottleName)"
                )
            }
        } catch {
            Logger.wineKit.error("DisplayPolicy failed: \(error.localizedDescription)")
        }
        return changed
    }

    public static func isRetinaEnabled(bottle: Bottle) -> Bool {
        WineRegistryFile.stringValue(
            bottle: bottle,
            keyPath: macDriverKey,
            name: "RetinaMode"
        ) == "y"
    }
}
