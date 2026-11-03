//
//  LaunchPathPreflight.swift
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

/// Renders the per-launch host-side policy (classic32 display tweaks)
/// with zero wine-process round-trips.
///
/// The legacy path cost 2–4 `wine reg` invocations (1.5–3.6 s each on
/// this class of machine) *after* wineserver startup, all to set two
/// values whose desired end-state is fully known at launch time:
/// `HKCU\Software\Wine\Mac Driver`→`RetinaMode=n` and
/// `HKCU\Control Panel\Desktop`→`LogPixels≤96`. Preflight writes both
/// values through the shared `WineRegistryFile` editor and records a
/// `WineIntentEnvelope` describing what was written.
///
/// The envelope is the anti-clobber contract. A live wineserver holds
/// the registry in memory and flushes on shutdown, which can overwrite
/// plain file edits (the bug behind 63c1faf). So after the spawn-phase
/// settles — when `LaunchPathPreflight.confirmIntent` runs — the values
/// are re-checked and, if a flush clobbered them, rewritten *while the
/// server is still alive*, which forces it to pick the new bytes up.
/// The write is only "confirmed" when the file content matches intent
/// after the launch has demonstrably been running with those semantics.
public struct WineIntentEnvelope: Codable, Sendable {
    public var keyPath: String
    public var name: String
    public var desiredString: String?
    public var desiredDword: Int?

    init(keyPath: String, name: String, desiredString: String? = nil, desiredDword: Int? = nil) {
        self.keyPath = keyPath
        self.name = name
        self.desiredString = desiredString
        self.desiredDword = desiredDword
    }
}

public enum LaunchPathPreflight {
    public static let macDriverKey = #"HKCU\Software\Wine\Mac Driver"#
    public static let desktopKey = #"HKCU\Control Panel\Desktop"#

    /// Apply classic32 display policy in-process. Returns the intents
    /// that describe the desired end state, for later confirmation.
    public static func applyClassic32(bottle: Bottle) -> [WineIntentEnvelope] {
        var intents: [WineIntentEnvelope] = []

        // RetinaMode: force off for classic32 (misrendering under
        // Retina scaling). Written idempotently; absence counts as "n"
        // in wine's mac driver, so a missing value needs no write.
        if WineRegistryFile.stringValue(
            bottle: bottle,
            keyPath: DisplayPolicy.macDriverKey,
            name: "RetinaMode"
        ) == "y" {
            try? WineRegistryFile.setStringValue(
                bottle: bottle,
                keyPath: DisplayPolicy.macDriverKey,
                name: "RetinaMode",
                value: "n"
            )
        }
        intents.append(WineIntentEnvelope(
            keyPath: DisplayPolicy.macDriverKey,
            name: "RetinaMode",
            desiredString: "n"
        ))

        // LogPixels: clamp to 96. dword values are stored lowercase hex
        // with 8 digits in .reg files.
        let current = WineRegistryFile.dwordValue(
            bottle: bottle,
            keyPath: DisplayPolicy.desktopKey,
            name: "LogPixels"
        )
        if current == nil || (current ?? 96) > 96 {
            try? WineRegistryFile.setDwordValue(
                bottle: bottle,
                keyPath: DisplayPolicy.desktopKey,
                name: "LogPixels",
                value: 96
            )
        }
        intents.append(WineIntentEnvelope(
            keyPath: DisplayPolicy.desktopKey,
            name: "LogPixels",
            desiredDword: 96
        ))

        return intents
    }

    /// Re-assert every intent against the current registry file,
    /// returning true when all values hold the desired state. Called
    /// once the launch phase has settled; if wineserver flushed an
    /// older in-memory registry over our writes, this rewrites the
    /// bytes while the server can still observe the change.
    @discardableResult
    public static func confirmIntent(
        bottle: Bottle,
        intents: [WineIntentEnvelope]
    ) -> Bool {
        var allHold = true
        for intent in intents {
            if let desired = intent.desiredString {
                if WineRegistryFile.stringValue(
                    bottle: bottle,
                    keyPath: intent.keyPath,
                    name: intent.name
                ) != desired {
                    try? WineRegistryFile.setStringValue(
                        bottle: bottle,
                        keyPath: intent.keyPath,
                        name: intent.name,
                        value: desired
                    )
                    allHold = false
                }
            }
            if let desired = intent.desiredDword {
                if WineRegistryFile.dwordValue(
                    bottle: bottle,
                    keyPath: intent.keyPath,
                    name: intent.name
                ) != desired {
                    try? WineRegistryFile.setDwordValue(
                        bottle: bottle,
                        keyPath: intent.keyPath,
                        name: intent.name,
                        value: desired
                    )
                    allHold = false
                }
            }
        }
        return allHold
    }
}
