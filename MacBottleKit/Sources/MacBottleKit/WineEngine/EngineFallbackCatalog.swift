//
//  EngineFallbackCatalog.swift
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

public struct EngineFallbackRelease: Sendable, Equatable {
    public let engineID: String
    public let displayName: String
    public let version: String
    public let url: URL
    public let sha256: String
    public let size: Int64
    public let licenseNote: String

    public init(
        engineID: String,
        displayName: String,
        version: String,
        url: URL,
        sha256: String,
        size: Int64,
        licenseNote: String
    ) {
        self.engineID = engineID
        self.displayName = displayName
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.licenseNote = licenseNote
    }
}

/// Pinned, checksummed fallback engines for when the archived Whisky
/// feed is unavailable. These are community Wine builds, not bundled
/// binaries; the app downloads from the upstream release page.
public enum EngineFallbackCatalog {
    public static let gcenxWine = EngineFallbackRelease(
        engineID: WineEngineCatalog.gcenxIdentifier,
        displayName: "Wine 11.21 (Gcenx, x86_64)",
        version: "11.21",
        url: {
            let urlString = "https://github.com/Gcenx/macOS_Wine_builds/releases/download/"
                + "11.21/wine-devel-11.21-osx64.tar.xz"
            guard let url = URL(string: urlString) else {
                preconditionFailure("invalid Gcenx Wine release URL")
            }
            return url
        }(),
        sha256: "9909b486657e10ab66c7279371ae1f990345b596b3b1b3a0cf21f28af24fa0ce",
        size: 225_612_636,
        licenseNote: "Wine is LGPL-2.1; this build is produced by Gcenx/macOS_Wine_builds."
    )

    public static var all: [EngineFallbackRelease] {
        [gcenxWine]
    }

    /// Prefer a signed remote manifest when it is reachable and valid;
    /// fall back to the digest compiled into the app. A missing/invalid
    /// signature does not silently upgrade to an unsigned release: the
    /// loader throws and the pinned catalog wins.
    public static func preferredFallback() async -> EngineFallbackRelease {
        guard let release = await signedRelease(engineID: gcenxWine.engineID) else {
            return gcenxWine
        }
        return EngineFallbackRelease(
            engineID: release.engineID,
            displayName: gcenxWine.displayName,
            version: release.version,
            url: release.url,
            sha256: release.sha256,
            size: release.size,
            licenseNote: gcenxWine.licenseNote
        )
    }

    public static func signedRelease(
        engineID: String,
        arch: String = "x86_64",
        loader: EngineManifestLoader = EngineManifestLoader(),
        publicKeyBase64: String? = EngineManifestLoader.bundledPublicKey()
    ) async -> EngineReleaseManifest.EngineRelease? {
        guard let manifest = try? await loader.load(publicKeyBase64: publicKeyBase64) else {
            return nil
        }
        return manifest.release(engineID: engineID, arch: arch)
    }

    public static func updateStatus(
        installed: SemanticVersion,
        remote: EngineReleaseManifest.EngineRelease?
    ) -> (hasUpdate: Bool, remoteVersion: SemanticVersion) {
        guard let remoteVersion = remote?.semanticVersion else {
            return (false, installed)
        }
        return (installed < remoteVersion, remoteVersion)
    }
}
