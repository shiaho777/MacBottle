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
    public static func apply(for profile: RuntimeProfile, bottle: Bottle) -> Bool {
        switch profile {
        case .classic32:
            return applyClassic32(bottle: bottle)
        case .modern64, .installer, .generic:
            return false
        }
    }

    @discardableResult
    public static func applyClassic32(bottle: Bottle) -> Bool {
        var changed = false
        do {
            if try WineRegistryFile.setStringValue(
                bottle: bottle,
                keyPath: macDriverKey,
                name: "RetinaMode",
                value: "n"
            ) {
                changed = true
            }
            let currentDPI = WineRegistryFile.dwordValue(
                bottle: bottle,
                keyPath: desktopKey,
                name: "LogPixels"
            )
            if currentDPI == nil || (currentDPI ?? 0) > 96 {
                if try WineRegistryFile.setDwordValue(
                    bottle: bottle,
                    keyPath: desktopKey,
                    name: "LogPixels",
                    value: 96
                ) {
                    changed = true
                }
            }
            if changed {
                Logger.wineKit.info("DisplayPolicy: classic32 applied RetinaMode=n LogPixels<=96 for \(bottle.settings.name)")
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
