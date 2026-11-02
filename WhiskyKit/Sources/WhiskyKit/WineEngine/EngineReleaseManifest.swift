//
//  EngineReleaseManifest.swift
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

import CryptoKit
import Foundation
import os.log

public struct EngineReleaseManifest: Codable, Sendable, Equatable {
    public let schema: Int
    public let generatedAt: String
    public let releases: [EngineRelease]
    public let signature: String?

    public struct EngineRelease: Codable, Sendable, Equatable {
        public let engineID: String
        public let version: String
        public let url: URL
        public let sha256: String
        public let size: Int64
        public let minMacOS: String
        public let arch: String

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case engineID = "engine_id"
            case version
            case url
            case sha256
            case size
            case minMacOS = "min_macos"
            case arch
        }

        public init(
            engineID: String,
            version: String,
            url: URL,
            sha256: String,
            size: Int64,
            minMacOS: String,
            arch: String
        ) {
            self.engineID = engineID
            self.version = version
            self.url = url
            self.sha256 = sha256
            self.size = size
            self.minMacOS = minMacOS
            self.arch = arch
        }
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case generatedAt = "generated_at"
        case releases
        case signature
    }

    public init(
        schema: Int = 1,
        generatedAt: String,
        releases: [EngineRelease],
        signature: String? = nil
    ) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.releases = releases
        self.signature = signature
    }

    /// Deterministic bytes covered by the signature. Kept deliberately
    /// simple (one line per release, fixed field order) so the signing
    /// script and the client cannot disagree about JSON key ordering.
    public var signingPayload: String {
        var lines = ["\(schema)", generatedAt]
        let sorted = releases.sorted {
            ($0.engineID, $0.arch) < ($1.engineID, $1.arch)
        }
        for release in sorted {
            lines.append([
                release.engineID,
                release.version,
                release.url.absoluteString,
                release.sha256,
                String(release.size),
                release.minMacOS,
                release.arch
            ].joined(separator: "|"))
        }
        return lines.joined(separator: "\n")
    }

    public func verify(publicKeyBase64: String) throws {
        guard schema == 1 else {
            throw EngineManifestError.unsupportedSchema(schema)
        }
        guard let signature,
              let signatureData = Data(base64Encoded: signature),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw EngineManifestError.invalidSignature
        }
        guard key.isValidSignature(signatureData, for: Data(signingPayload.utf8)) else {
            throw EngineManifestError.invalidSignature
        }
    }

    public func release(
        engineID: String,
        arch: String,
        macOS: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> EngineRelease? {
        releases
            .filter { $0.engineID == engineID && $0.arch == arch }
            .filter { $0.minMacOS.isSatisfied(by: macOS) }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
            .first
    }
}

extension String {
    func isSatisfied(by version: OperatingSystemVersion) -> Bool {
        let parts = split(separator: ".", omittingEmptySubsequences: false)
        guard let major = Int(parts.first ?? "") else { return false }
        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        if version.majorVersion != major {
            return version.majorVersion > major
        }
        return version.minorVersion >= minor
    }
}

public enum EngineManifestError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case invalidSignature
    case noMatchingRelease(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported engine manifest schema \(schema)."
        case .invalidSignature:
            return "The engine manifest signature is invalid."
        case .noMatchingRelease(let engineID):
            return "No engine release matches \(engineID) on this Mac."
        }
    }
}

public struct EngineManifestLoader: Sendable {
    public static let defaultURL: URL = {
        guard let url = URL(
            string: "https://raw.githubusercontent.com/shiaho777/MacBottle/main/engine-manifest.json"
        ) else {
            preconditionFailure("invalid engine manifest URL")
        }
        return url
    }()

    public let url: URL
    private let fetcher: @Sendable (URL) async throws -> Data

    public init(
        url: URL = EngineManifestLoader.defaultURL,
        fetcher: (@Sendable (URL) async throws -> Data)? = nil
    ) {
        self.url = url
        self.fetcher = fetcher ?? { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    public func load(publicKeyBase64: String?) async throws -> EngineReleaseManifest {
        let data = try await fetcher(url)
        let manifest = try JSONDecoder().decode(EngineReleaseManifest.self, from: data)
        if let publicKeyBase64 {
            try manifest.verify(publicKeyBase64: publicKeyBase64)
        }
        return manifest
    }

    /// The public key is baked into the app bundle, so the manifest's
    /// trust root travels with the notarized binary rather than with the
    /// JSON file it describes.
    public static func bundledPublicKey(bundle: Bundle = .main) -> String? {
        bundle.object(forInfoDictionaryKey: "MBEngineManifestPublicKey") as? String
    }
}
