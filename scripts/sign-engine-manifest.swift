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
//  The corresponding public key is embedded in Whisky/Info.plist as
//  MBEngineManifestPublicKey. Rotating the key pair requires updating
//  both, which is deliberate: the trust root ships with the notarized app.
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

    enum CodingKeys: String, CodingKey {
        case engineID = "engine_id"
        case version
        case url
        case sha256
        case size
        case minMacOS = "min_macos"
        case arch
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

func signingPayload(_ manifest: Manifest) -> String {
    var lines = ["\(manifest.schema)", manifest.generatedAt]
    for release in manifest.releases.sorted(by: {
        ($0.engineID, $0.arch) < ($1.engineID, $1.arch)
    }) {
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
