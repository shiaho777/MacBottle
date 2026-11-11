//
//  EngineReleaseManifestTests.swift
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
import SemanticVersion
import XCTest
@testable import MacBottleKit

final class EngineReleaseManifestTests: XCTestCase {
    private func makeRelease(
        version: String = "11.21",
        engineID: String = "gcenx-wine",
        arch: String = "x86_64",
        minMacOS: String = "14.0",
        displayName: String? = nil,
        kind: EnginePackageKind? = nil,
        capabilities: [String] = [],
        installLayout: EngineInstallLayout? = nil
    ) -> EngineReleaseManifest.EngineRelease {
        guard let url = URL(string: "https://example.com/\(engineID).tar.xz") else {
            preconditionFailure("invalid fixture URL")
        }
        return EngineReleaseManifest.EngineRelease(
            engineID: engineID,
            version: version,
            url: url,
            sha256: String(repeating: "a", count: 64),
            size: 123,
            minMacOS: minMacOS,
            arch: arch,
            displayName: displayName,
            kind: kind,
            capabilities: capabilities,
            packageFormat: displayName == nil ? nil : "tar.xz",
            installLayout: installLayout,
            channel: displayName == nil ? nil : "stable",
            license: displayName == nil ? nil : "LGPL-2.1",
            notes: displayName == nil ? nil : "fixture"
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
                + "gcenx-wine|11.21|https://example.com/gcenx-wine.tar.xz|"
                + String(repeating: "a", count: 64)
                + "|123|14.0|x86_64"
        )
    }

    func testSchema2SigningPayloadIncludesPackageMetadata() {
        let release = makeRelease(
            displayName: "Wine 11.21 (Gcenx, x86_64)",
            kind: .wine,
            capabilities: ["wine", "x86_64", "rosetta"],
            installLayout: .gcenxAppBundle
        )
        let manifest = EngineReleaseManifest(
            schema: 2,
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [release]
        )
        XCTAssertEqual(
            manifest.signingPayload,
            "2\n2026-11-02T00:00:00Z\n"
                + "gcenx-wine|11.21|https://example.com/gcenx-wine.tar.xz|"
                + String(repeating: "a", count: 64)
                + "|123|14.0|x86_64"
                + "|Wine 11.21 (Gcenx, x86_64)|wine|rosetta,wine,x86_64"
                + "|tar.xz|gcenx-app-bundle|stable|LGPL-2.1|fixture"
        )
    }

    func testSchema1ReleaseDecodesWithoutSchema2Fields() throws {
        let json = """
        {
          "schema": 1,
          "generated_at": "2026-11-02T00:00:00Z",
          "releases": [
            {
              "engine_id": "legacy",
              "version": "11.0",
              "url": "https://example.com/legacy.tar.xz",
              "sha256": "\(String(repeating: "b", count: 64))",
              "size": 1,
              "min_macos": "14.0",
              "arch": "x86_64"
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(
            EngineReleaseManifest.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(manifest.schema, 1)
        XCTAssertEqual(manifest.releases.first?.capabilities, [])
        XCTAssertEqual(manifest.releases.first?.resolvedKind, .custom)
        XCTAssertEqual(manifest.releases.first?.resolvedInstallLayout, .wineRoot)
        XCTAssertNil(manifest.releases.first?.displayName)
    }

    func testSchema2TamperingWithMetadataFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let release = makeRelease(
            displayName: "Wine 11.21 (Gcenx, x86_64)",
            kind: .wine,
            capabilities: ["wine"],
            installLayout: .gcenxAppBundle
        )
        let unsigned = EngineReleaseManifest(
            schema: 2,
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [release]
        )
        let signature = try key.signature(for: Data(unsigned.signingPayload.utf8))
            .base64EncodedString()
        let signed = EngineReleaseManifest(
            schema: 2,
            generatedAt: unsigned.generatedAt,
            releases: unsigned.releases,
            signature: signature
        )
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertNoThrow(try signed.verify(publicKeyBase64: publicKey))

        let tamperedRelease = makeRelease(
            displayName: "Wine 99 (evil)",
            kind: .wine,
            capabilities: ["wine"],
            installLayout: .gcenxAppBundle
        )
        let tampered = EngineReleaseManifest(
            schema: 2,
            generatedAt: signed.generatedAt,
            releases: [tamperedRelease],
            signature: signature
        )
        XCTAssertThrowsError(try tampered.verify(publicKeyBase64: publicKey))
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

    func testLatestReleasesPrefersNewerVersionOverNativeArch() {
        let manifest = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [
                makeRelease(version: "11.21", engineID: "engine", arch: "arm64"),
                makeRelease(version: "11.22", engineID: "engine", arch: "x86_64")
            ]
        )
        let latest = manifest.latestReleases(
            compatibleArchitectures: ["arm64", "x86_64"],
            macOS: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        )
        XCTAssertEqual(latest.count, 1)
        XCTAssertEqual(latest.first?.version, "11.22")
        XCTAssertEqual(latest.first?.arch, "x86_64")
    }

    func testLatestReleasesPrefersNativeArchOnVersionTie() {
        let manifest = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [
                makeRelease(version: "11.21", engineID: "engine", arch: "x86_64"),
                makeRelease(version: "11.21", engineID: "engine", arch: "arm64")
            ]
        )
        let latest = manifest.latestReleases(
            compatibleArchitectures: ["arm64", "x86_64"],
            macOS: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        )
        XCTAssertEqual(latest.count, 1)
        XCTAssertEqual(latest.first?.arch, "arm64")
    }

    func testLatestReleasesFiltersByMinimumMacOS() {
        let manifest = EngineReleaseManifest(
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [
                makeRelease(engineID: "old", arch: "arm64", minMacOS: "14.0"),
                makeRelease(engineID: "new", arch: "arm64", minMacOS: "15.0")
            ]
        )
        let latest = manifest.latestReleases(
            compatibleArchitectures: ["arm64"],
            macOS: OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)
        )
        XCTAssertEqual(latest.map(\.engineID), ["old"])
    }

    func testPackageCatalogUsesManifestIdentityAndInstallSlot() {
        let manifest = EngineReleaseManifest(
            schema: 2,
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [
                makeRelease(
                    engineID: "macbottle-arm64",
                    arch: "arm64",
                    displayName: "MacBottle Wine (ARM64)",
                    kind: .wine,
                    capabilities: ["wine", "arm64"],
                    installLayout: .wineRoot
                )
            ]
        )
        let packages = EnginePackageCatalog.packages(
            from: manifest,
            compatibleArchitectures: ["arm64"],
            macOS: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        )
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages.first?.id, "macbottle-arm64")
        XCTAssertEqual(packages.first?.displayName, "MacBottle Wine (ARM64)")
        XCTAssertEqual(packages.first?.engine.identifier, "macbottle-arm64")
        XCTAssertEqual(packages.first?.engine.manifestEngineID, "macbottle-arm64")
        XCTAssertEqual(packages.first?.kind, .wine)
    }

    func testPackageCatalogKeepsLegacyCrossOverSlot() {
        let manifest = EngineReleaseManifest(
            schema: 2,
            generatedAt: "2026-11-02T00:00:00Z",
            releases: [
                makeRelease(
                    engineID: "crossover",
                    arch: "arm64",
                    displayName: "CrossOver Wine",
                    kind: .crossover,
                    installLayout: .wineRoot
                )
            ]
        )
        let packages = EnginePackageCatalog.packages(
            from: manifest,
            compatibleArchitectures: ["arm64"],
            macOS: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        )
        XCTAssertEqual(packages.first?.engine.libraryRoot.lastPathComponent, "Libraries")
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
        XCTAssertEqual(manifest.schema, 2)
        let release = manifest.release(engineID: "gcenx-wine", arch: "x86_64")
        XCTAssertEqual(release?.resolvedDisplayName, "Wine 11.21 (Gcenx, x86_64)")
        XCTAssertEqual(release?.resolvedKind, .wine)
        XCTAssertEqual(release?.resolvedInstallLayout, .gcenxAppBundle)
        XCTAssertTrue(release?.supports("rosetta") == true)
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
