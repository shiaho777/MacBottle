//
//  SteamCredentials.swift
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

public struct SteamCredentials: Sendable, Equatable {
    public var username: String
    public var password: String
    public var steamGuardCode: String?

    public init(username: String, password: String, steamGuardCode: String? = nil) {
        self.username = username
        self.password = password
        self.steamGuardCode = steamGuardCode
    }

    public static let anonymous = SteamCredentials(username: "anonymous", password: "")

    public var isAnonymous: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "anonymous"
    }
}

public enum SteamAppID {
    public static func parse(fromRecipeID recipeID: String) -> Int? {
        let parts = recipeID.split(separator: ".")
        guard parts.count >= 2, parts[0] == "steam" else { return nil }
        return Int(parts[1])
    }
}
