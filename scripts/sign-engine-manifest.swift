#!/usr/bin/env swift
//
//  sign-engine-manifest.swift
//  MacBottle
//
//  Computes the canonical payload of `engine-manifest.json`, signs it with
//  the Ed25519 private key, and writes the base64 signature back.
//
//  Usage:
//      MACBOTTLE_ENGINE_SIGNING_KEY=<base64> \
//          swift scripts/sign-engine-manifest.swift [engine-manifest.json]
//
//  The corresponding public key is embedded in MacBottle/Info.plist as
//  MBEngineManifestPublicKey. Rotating the key pair requires updating
//  both, which is deliberate: the trust root ships with the notarized app.
//
//  Schema 2 appends package metadata to the payload. Keep this file in
//  lockstep with EngineReleaseManifest.signingPayload in MacBottleKit.
//

import CryptoKit
import Foundation

struct Release: Codable {
    let engineID: String
    let version: String
    let url: URL
    let sha256: String
    let size: Int64
    let minMacOS: String
    let arch: String
    let displayName: String?
    let kind: String?
    let capabilities: [String]
    let packageFormat: String?
    let installLayout: String?
    let channel: String?
    let license: String?
    let notes: String?

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engineID = try container.decode(String.self, forKey: .engineID)
        version = try container.decode(String.self, forKey: .version)
        url = try container.decode(URL.self, forKey: .url)
        sha256 = try container.decode(String.self, forKey: .sha256)
        size = try container.decode(Int64.self, forKey: .size)
        minMacOS = try container.decode(String.self, forKey: .minMacOS)
        arch = try container.decode(String.self, forKey: .arch)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        packageFormat = try container.decodeIfPresent(String.self, forKey: .packageFormat)
        installLayout = try container.decodeIfPresent(String.self, forKey: .installLayout)
        channel = try container.decodeIfPresent(String.self, forKey: .channel)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct Manifest: Codable {
    let schema: Int
    let generatedAt: String
    let releases: [Release]
    var signature: String?

    enum CodingKeys: String, CodingKey {
        case schema
        case generatedAt = "generated_at"
        case releases
        case signature
    }
}

func signingField(_ value: String?) -> String {
    guard let value else { return "" }
    return value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "|", with: "\\|")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
}

func signingPayload(_ manifest: Manifest) -> String {
    var lines = ["\(manifest.schema)", manifest.generatedAt]
    for release in manifest.releases.sorted(by: {
        ($0.engineID, $0.arch) < ($1.engineID, $1.arch)
    }) {
        var fields = [
            release.engineID,
            release.version,
            release.url.absoluteString,
            release.sha256,
            String(release.size),
            release.minMacOS,
            release.arch
        ]
        if manifest.schema >= 2 {
            let kind = release.kind ?? "custom"
            let layout = release.installLayout ?? "wine-root"
            guard ["wine", "crossover", "gptk", "custom"].contains(kind) else {
                fatalError("invalid engine kind '\(kind)' for \(release.engineID)")
            }
            guard ["wine-root", "gcenx-app-bundle"].contains(layout) else {
                fatalError("invalid install_layout '\(layout)' for \(release.engineID)")
            }
            fields.append(contentsOf: [
                signingField(release.displayName),
                kind,
                release.capabilities.sorted().joined(separator: ","),
                signingField(release.packageFormat),
                layout,
                signingField(release.channel),
                signingField(release.license),
                signingField(release.notes)
            ])
        }
        lines.append(fields.joined(separator: "|"))
    }
    return lines.joined(separator: "\n")
}

let path = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "engine-manifest.json"
let keyBase64: String
if let environment = ProcessInfo.processInfo.environment["MACBOTTLE_ENGINE_SIGNING_KEY"],
   !environment.isEmpty {
    keyBase64 = environment
} else {
    let keyURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".macbottle-engine-signing-key")
    keyBase64 = try String(contentsOf: keyURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

let url = URL(fileURLWithPath: path)
let decoder = JSONDecoder()
var manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: url))
let key = try Curve25519.Signing.PrivateKey(
    rawRepresentation: Data(base64Encoded: keyBase64)!
)
let signature = try key.signature(for: Data(signingPayload(manifest).utf8))
manifest.signature = signature.base64EncodedString()

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(manifest).write(to: url, options: .atomic)
print("signed \(path) with \(key.publicKey.rawRepresentation.base64EncodedString())")
