//
//  ProgramSettings.swift
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

public enum Locales: String, Codable, CaseIterable {
    case auto = ""
    case german = "de_DE.UTF-8"
    case english = "en_US"
    case spanish = "es_ES.UTF-8"
    case french = "fr_FR.UTF-8"
    case italian = "it_IT.UTF-8"
    case japanese = "ja_JP.UTF-8"
    case korean = "ko_KR.UTF-8"
    case russian = "ru_RU.UTF-8"
    case ukranian = "uk_UA.UTF-8"
    case thai = "th_TH.UTF-8"
    case chineseSimplified = "zh_CN.UTF-8"
    case chineseTraditional = "zh_TW.UTF-8"

    public func pretty() -> String {
        switch self {
        case .auto:
            return String(localized: "locale.auto")
        case .german:
            return "Deutsch"
        case .english:
            return "English"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        case .italian:
            return "Italiano"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .russian:
            return "Русский"
        case .ukranian:
            return "Українська"
        case .thai:
            return "ไทย"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        }
    }
}

public struct ProgramSettings: Codable {
    public var locale: Locales = .auto
    public var environment: [String: String] = [:]
    public var arguments: String = ""
    public var recipeID: String?
    public var lastLaunchedAt: Date?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case locale, environment, arguments, recipeID, lastLaunchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.locale = try container.decodeIfPresent(Locales.self, forKey: .locale) ?? .auto
        self.environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        self.arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        self.recipeID = try container.decodeIfPresent(String.self, forKey: .recipeID)
        self.lastLaunchedAt = try container.decodeIfPresent(Date.self, forKey: .lastLaunchedAt)
    }

    static func decode(from settingsURL: URL) throws -> ProgramSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)) else {
            let settings = ProgramSettings()
            try settings.encode(to: settingsURL)
            return settings
        }

        let data = try Data(contentsOf: settingsURL)
        return try PropertyListDecoder().decode(ProgramSettings.self, from: data)
    }

    func encode(to settingsURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: settingsURL)
    }
}
