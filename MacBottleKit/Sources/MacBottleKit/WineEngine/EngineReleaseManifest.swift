//
//  EngineReleaseManifest.swift
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

import CryptoKit
import Foundation
import os.log
import SemanticVersion

public enum EnginePackageKind: String, Codable, Sendable, CaseIterable {
    /// Upstream or community Wine build.
    case wine
    /// CrossOver-derived Wine packaging.
    case crossover
    /// Apple Game Porting Toolkit runtime.
    case gptk
    /// Any other engine bundle.
    case custom
}

public enum EngineInstallLayout: String, Codable, Sendable, CaseIterable {
    /// Archive root contains `Wine/bin/wine`.
    case wineRoot = "wine-root"
    /// Gcenx-style app bundle: `Wine Devel.app/Contents/Resources/wine`.
    case gcenxAppBundle = "gcenx-app-bundle"
}

public struct EngineReleaseManifest: Codable, Sendable, Equatable {
    public static let supportedSchemas = [1, 2]

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

        // Schema 2 package metadata. Optional so schema 1 manifests keep
        // decoding and verifying exactly as before.
        public let displayName: String?
        public let kind: EnginePackageKind?
        public let capabilities: [String]
        public let packageFormat: String?
        public let installLayout: EngineInstallLayout?
        public let channel: String?
        public let license: String?
        public let notes: String?

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case engineID = "engine_id"
            case version
            case url
            case sha256
            case size
            case minMacOS = "min_macos"
            case arch
            case displayName = "display_name"
            case kind
            case capabilities
            case packageFormat = "package_format"
            case installLayout = "install_layout"
            case channel
            case license
            case notes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            engineID = try container.decode(String.self, forKey: .engineID)
            version = try container.decode(String.self, forKey: .version)
            url = try container.decode(URL.self, forKey: .url)
            sha256 = try container.decode(String.self, forKey: .sha256)
            size = try container.decode(Int64.self, forKey: .size)
            minMacOS = try container.decode(String.self, forKey: .minMacOS)
            arch = try container.decode(String.self, forKey: .arch)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            kind = try container.decodeIfPresent(EnginePackageKind.self, forKey: .kind)
            capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
            packageFormat = try container.decodeIfPresent(String.self, forKey: .packageFormat)
            installLayout = try container.decodeIfPresent(EngineInstallLayout.self, forKey: .installLayout)
            channel = try container.decodeIfPresent(String.self, forKey: .channel)
            license = try container.decodeIfPresent(String.self, forKey: .license)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
        }

        public init(
            engineID: String,
            version: String,
            url: URL,
            sha256: String,
            size: Int64,
            minMacOS: String,
            arch: String,
            displayName: String? = nil,
            kind: EnginePackageKind? = nil,
            capabilities: [String] = [],
            packageFormat: String? = nil,
            installLayout: EngineInstallLayout? = nil,
            channel: String? = nil,
            license: String? = nil,
            notes: String? = nil
        ) {
            self.engineID = engineID
            self.version = version
            self.url = url
            self.sha256 = sha256
            self.size = size
            self.minMacOS = minMacOS
            self.arch = arch
            self.displayName = displayName
            self.kind = kind
            self.capabilities = capabilities
            self.packageFormat = packageFormat
            self.installLayout = installLayout
            self.channel = channel
            self.license = license
            self.notes = notes
        }

        public var semanticVersion: SemanticVersion? {
            let parts = version.split(separator: ".", omittingEmptySubsequences: false)
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

        public var resolvedDisplayName: String {
            displayName ?? engineID
        }

        public var resolvedKind: EnginePackageKind {
            kind ?? .custom
        }

        public var resolvedInstallLayout: EngineInstallLayout {
            installLayout ?? .wineRoot
        }

        public func supports(_ capability: String) -> Bool {
            capabilities.contains { $0.caseInsensitiveCompare(capability) == .orderedSame }
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
    ///
    /// Schema 1 stops after `arch`. Schema 2 appends the package metadata
    /// that drives the install UI and the generic installer, so a manifest
    /// cannot advertise one engine and deliver another.
    public var signingPayload: String {
        var lines = ["\(schema)", generatedAt]
        let sorted = releases.sorted {
            ($0.engineID, $0.arch) < ($1.engineID, $1.arch)
        }
        for release in sorted {
            var fields = [
                release.engineID,
                release.version,
                release.url.absoluteString,
                release.sha256,
                String(release.size),
                release.minMacOS,
                release.arch
            ]
            if schema >= 2 {
                fields.append(contentsOf: [
                    Self.signingField(release.displayName),
                    release.resolvedKind.rawValue,
                    release.capabilities.sorted().joined(separator: ","),
                    Self.signingField(release.packageFormat),
                    release.resolvedInstallLayout.rawValue,
                    Self.signingField(release.channel),
                    Self.signingField(release.license),
                    Self.signingField(release.notes)
                ])
            }
            lines.append(fields.joined(separator: "|"))
        }
        return lines.joined(separator: "\n")
    }

    private static func signingField(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    public func verify(publicKeyBase64: String) throws {
        guard Self.supportedSchemas.contains(schema) else {
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

    /// The architectures this Mac can run, native first. An Apple Silicon
    /// Mac can still run an x86_64 Wine build through Rosetta, so the
    /// catalog must not hide those packages; a version newer than the
    /// native one still wins.
    public static var compatibleArchitectures: [String] {
        #if arch(arm64)
        ["arm64", "x86_64"]
        #else
        ["x86_64"]
        #endif
    }

    /// One newest compatible release per engine. Ties on version prefer
    /// the earlier architecture in `compatibleArchitectures`, so a native
    /// arm64 build beats an x86_64 build of the same version.
    public func latestReleases(
        compatibleArchitectures: [String] = EngineReleaseManifest.compatibleArchitectures,
        macOS: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> [EngineRelease] {
        let candidates = releases.filter {
            compatibleArchitectures.contains($0.arch) && $0.minMacOS.isSatisfied(by: macOS)
        }
        return Dictionary(grouping: candidates, by: \.engineID)
            .compactMap { _, group in
                group.max { lhs, rhs in
                    let left = lhs.semanticVersion ?? SemanticVersion(0, 0, 0)
                    let right = rhs.semanticVersion ?? SemanticVersion(0, 0, 0)
                    if left != right {
                        return left < right
                    }
                    let leftIndex = compatibleArchitectures.firstIndex(of: lhs.arch) ?? Int.max
                    let rightIndex = compatibleArchitectures.firstIndex(of: rhs.arch) ?? Int.max
                    return leftIndex > rightIndex
                }
            }
            .sorted { $0.engineID < $1.engineID }
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
    case missingPublicKey
    case noMatchingRelease(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported engine manifest schema \(schema)."
        case .invalidSignature:
            return "The engine manifest signature is invalid."
        case .missingPublicKey:
            return "No engine manifest public key is configured."
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
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    public func load(publicKeyBase64: String?) async throws -> EngineReleaseManifest {
        guard let publicKeyBase64, !publicKeyBase64.isEmpty else {
            throw EngineManifestError.missingPublicKey
        }
        let data = try await fetcher(url)
        let manifest = try JSONDecoder().decode(EngineReleaseManifest.self, from: data)
        try manifest.verify(publicKeyBase64: publicKeyBase64)
        return manifest
    }

    /// The public key is baked into the app bundle, so the manifest's
    /// trust root travels with the notarized binary rather than with the
    /// JSON file it describes.
    public static func bundledPublicKey(bundle: Bundle = .main) -> String? {
        bundle.object(forInfoDictionaryKey: "MBEngineManifestPublicKey") as? String
    }
}
