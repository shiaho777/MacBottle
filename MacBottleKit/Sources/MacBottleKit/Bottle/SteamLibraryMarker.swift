//
//  SteamLibraryMarker.swift
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

/// Marks a bottle as the shared Steam library. One bottle can host many
/// Steam titles, their depot cache, and a single Steam client, instead of
/// duplicating that tree per game.
public enum SteamLibraryMarker {
    public static let fileName = ".macbottle_steam_library"

    public static func isMarked(_ bottle: Bottle) -> Bool {
        FileManager.default.fileExists(
            atPath: url(for: bottle).path(percentEncoded: false)
        )
    }

    public static func mark(_ bottle: Bottle) throws {
        try Data().write(to: url(for: bottle), options: .atomic)
    }

    public static func find(in bottles: [Bottle]) -> Bottle? {
        bottles
            .filter(\.isAvailable)
            .first(where: isMarked)
    }

    private static func url(for bottle: Bottle) -> URL {
        bottle.url.appending(path: fileName)
    }
}
