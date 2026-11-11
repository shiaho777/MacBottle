//
//  AppUpdateChecker.swift
//  MacBottleKit
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
import SemanticVersion

public struct AppRelease: Sendable, Equatable {
    public let version: SemanticVersion
    public let tagName: String
    public let pageURL: URL

    public init(version: SemanticVersion, tagName: String, pageURL: URL) {
        self.version = version
        self.tagName = tagName
        self.pageURL = pageURL
    }
}

public enum AppUpdateStatus: Sendable, Equatable {
    case upToDate(current: SemanticVersion)
    case available(AppRelease)
    case noPublishedRelease
}

public enum AppUpdateError: Error, LocalizedError, Equatable {
    case badResponse(Int)
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "The update server returned HTTP \(status)."
        case .invalidPayload:
            return "The latest release could not be read."
        }
    }
}

public struct AppUpdateChecker: Sendable {
    public static let defaultURL: URL = {
        guard let url = URL(
            string: "https://api.github.com/repos/shiaho777/MacBottle/releases/latest"
        ) else {
            preconditionFailure("AppUpdateChecker.defaultURL: hardcoded URL failed to parse")
        }
        return url
    }()

    public static let releasesPageURL: URL = {
        guard let url = URL(string: "https://github.com/shiaho777/MacBottle/releases") else {
            preconditionFailure("AppUpdateChecker.releasesPageURL: hardcoded URL failed to parse")
        }
        return url
    }()

    public let url: URL
    private let fetcher: @Sendable (URL) async throws -> (Data, Int)

    public init(
        url: URL = AppUpdateChecker.defaultURL,
        fetcher: (@Sendable (URL) async throws -> (Data, Int))? = nil
    ) {
        self.url = url
        self.fetcher = fetcher ?? { url in
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MacBottle", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        }
    }

    public func check(currentVersion: SemanticVersion) async throws -> AppUpdateStatus {
        let (data, status) = try await fetcher(url)
        if status == 404 {
            return .noPublishedRelease
        }
        guard (200..<300).contains(status) else {
            throw AppUpdateError.badResponse(status)
        }
        guard let payload = try? JSONDecoder().decode(LatestReleasePayload.self, from: data),
              !payload.draft,
              !payload.prerelease,
              let version = Self.parseVersion(payload.tagName),
              let pageURL = URL(string: payload.htmlURL) else {
            throw AppUpdateError.invalidPayload
        }
        guard currentVersion < version else {
            return .upToDate(current: currentVersion)
        }
        return .available(AppRelease(version: version, tagName: payload.tagName, pageURL: pageURL))
    }

    public static func parseVersion(_ text: String) -> SemanticVersion? {
        var core = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if core.first == "v" || core.first == "V" {
            core = core.dropFirst()
        }
        if let suffix = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = core[..<suffix]
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else {
                return nil
            }
            numbers.append(value)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }
        return SemanticVersion(numbers[0], numbers[1], numbers[2])
    }

    public static func currentVersion(bundle: Bundle = .main) -> SemanticVersion? {
        guard let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return parseVersion(text)
    }
}

private struct LatestReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}
