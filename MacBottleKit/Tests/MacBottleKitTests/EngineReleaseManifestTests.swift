//
//  EngineReleaseManifestTests.swift
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
import SemanticVersion
import XCTest
@testable import MacBottleKit

final class EngineReleaseManifestTests: XCTestCase {
    private func makeRelease(version: String = "11.21") -> EngineReleaseManifest.EngineRelease {
        guard let url = URL(string: "https://example.com/wine.tar.xz") else {
            preconditionFailure("invalid fixture URL")
        }
        return EngineReleaseManifest.EngineRelease(
            engineID: "gcenx-wine",
            version: version,
            url: url,
            sha256: String(repeating: "a", count: 64),
            size: 123,
            minMacOS: "14.0",
            arch: "x86_64"
        )
    }

    func testSigningPayloadIsDeterministic() {
        let manifest = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [makeRelease()]
        )
        XCTAssertEqual(
            manifest.signingPayload,
            "1\n2026-11-02T00:00:00Z\n"
                + "gcenx-wine|11.21|https://example.com/wine.tar.xz|"
                + String(repeating: "a", count: 64)
                + "|123|14.0|x86_64"
        )
    }

    func testValidSignatureVerifiesAndTamperFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let unsigned = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [makeRelease()]
        )
        let signature = try key.signature(
            for: Data(unsigned.signingPayload.utf8)
        ).base64EncodedString()
        let signed = EngineReleaseManifest(
            generatedAt: unsigned.generatedAt,
            releases: unsigned.releases,
            signature: signature
        )
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertNoThrow(try signed.verify(publicKeyBase64: publicKey))

        let tampered = EngineReleaseManifest(
            generatedAt: signed.generatedAt,
            releases: [makeRelease(version: "99.0")],
            signature: signature
        )
        XCTAssertThrowsError(try tampered.verify(publicKeyBase64: publicKey))
    }

    func testSelectsNewestMatchingReleaseForMacOS() {
        let manifest = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [makeRelease(version: "10.0"), makeRelease(version: "11.21")]
        )
        let macOS = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        XCTAssertEqual(manifest.release(engineID: "gcenx-wine", arch: "x86_64", macOS: macOS)?.version, "11.21")
        XCTAssertNil(manifest.release(engineID: "other", arch: "x86_64", macOS: macOS))
    }

    func testRepositoryManifestVerifiesWithBundledKey() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repoRoot.appending(path: "engine-manifest.json"))
        let manifest = try JSONDecoder().decode(EngineReleaseManifest.self, from: data)
        let publicKey = "abqGeOEAtB1ntAlCsNNbi80AfWP3Tsgn3X9IWXFsLnI="
        XCTAssertNoThrow(try manifest.verify(publicKeyBase64: publicKey))
        XCTAssertNotNil(manifest.release(engineID: "gcenx-wine", arch: "x86_64"))
    }

    func testLoaderDecodesAndVerifies() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let unsigned = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [makeRelease()]
        )
        let signature = try key.signature(for: Data(unsigned.signingPayload.utf8))
            .base64EncodedString()
        let signed = EngineReleaseManifest(
            generatedAt: unsigned.generatedAt,
            releases: unsigned.releases,
            signature: signature
        )
        let data = try JSONEncoder().encode(signed)
        let loader = EngineManifestLoader(
            url: URL(fileURLWithPath: "/tmp/manifest.json"),
            fetcher: { _ in data }
        )
        let loaded = try await loader.load(
            publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
        )
        XCTAssertEqual(loaded.releases, signed.releases)
    }

    func testLoaderFailsClosedWithoutPublicKey() async {
        let loader = EngineManifestLoader(
            url: URL(fileURLWithPath: "/tmp/manifest.json"),
            fetcher: { _ in
                XCTFail("fetcher must not run without a public key")
                return Data()
            }
        )
        for key in [nil, ""] as [String?] {
            do {
                _ = try await loader.load(publicKeyBase64: key)
                XCTFail("expected missingPublicKey")
            } catch EngineManifestError.missingPublicKey {
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testReleaseVersionParsing() {
        XCTAssertEqual(makeRelease(version: "11.21").semanticVersion, SemanticVersion(11, 21, 0))
        XCTAssertEqual(makeRelease(version: "11").semanticVersion, SemanticVersion(11, 0, 0))
        XCTAssertEqual(makeRelease(version: "11.21.3").semanticVersion, SemanticVersion(11, 21, 3))
        XCTAssertNil(makeRelease(version: "").semanticVersion)
        XCTAssertNil(makeRelease(version: "11.").semanticVersion)
        XCTAssertNil(makeRelease(version: "11.21-rc1").semanticVersion)
        XCTAssertNil(makeRelease(version: "1.2.3.4").semanticVersion)
    }

    func testUpdateStatusComparesVersions() {
        let installed = SemanticVersion(11, 21, 0)

        let newer = EngineFallbackCatalog.updateStatus(installed: installed, remote: makeRelease(version: "11.22"))
        XCTAssertTrue(newer.hasUpdate)
        XCTAssertEqual(newer.remoteVersion, SemanticVersion(11, 22, 0))

        let same = EngineFallbackCatalog.updateStatus(installed: installed, remote: makeRelease(version: "11.21"))
        XCTAssertFalse(same.hasUpdate)

        let older = EngineFallbackCatalog.updateStatus(installed: installed, remote: makeRelease(version: "11.20"))
        XCTAssertFalse(older.hasUpdate)

        let missing = EngineFallbackCatalog.updateStatus(installed: installed, remote: nil)
        XCTAssertFalse(missing.hasUpdate)
        XCTAssertEqual(missing.remoteVersion, installed)

        let unparsable = EngineFallbackCatalog.updateStatus(installed: installed, remote: makeRelease(version: "next"))
        XCTAssertFalse(unparsable.hasUpdate)
    }

    func testSignedReleaseRequiresValidSignature() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let unsigned = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [makeRelease(version: "11.22")]
        )
        let signature = try key.signature(for: Data(unsigned.signingPayload.utf8))
            .base64EncodedString()
        let signed = EngineReleaseManifest(
            generatedAt: unsigned.generatedAt,
            releases: unsigned.releases,
            signature: signature
        )
        let data = try JSONEncoder().encode(signed)
        let loader = EngineManifestLoader(
            url: URL(fileURLWithPath: "/tmp/manifest.json"),
            fetcher: { _ in data }
        )
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()

        let found = await EngineFallbackCatalog.signedRelease(
            engineID: "gcenx-wine",
            loader: loader,
            publicKeyBase64: publicKey
        )
        XCTAssertEqual(found?.version, "11.22")

        let noKey = await EngineFallbackCatalog.signedRelease(
            engineID: "gcenx-wine",
            loader: loader,
            publicKeyBase64: nil
        )
        XCTAssertNil(noKey)

        let wrongKey = await EngineFallbackCatalog.signedRelease(
            engineID: "gcenx-wine",
            loader: loader,
            publicKeyBase64: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        )
        XCTAssertNil(wrongKey)

        let otherEngine = await EngineFallbackCatalog.signedRelease(
            engineID: "other-engine",
            loader: loader,
            publicKeyBase64: publicKey
        )
        XCTAssertNil(otherEngine)
    }
}
