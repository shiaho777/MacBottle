//
//  EnginePackage.swift
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
import os.log

/// A signed engine package from `engine-manifest.json` plus the on-disk
/// slot it installs into. The manifest owns the metadata; the engine
/// owns the paths.
public struct EnginePackage: Sendable, Equatable, Identifiable {
    public let release: EngineReleaseManifest.EngineRelease
    public let engine: LocalPathEngine

    public init(
        release: EngineReleaseManifest.EngineRelease,
        engine: LocalPathEngine
    ) {
        self.release = release
        self.engine = engine
    }

    public var id: String { release.engineID }
    public var displayName: String { release.resolvedDisplayName }
    public var version: String { release.version }
    public var kind: EnginePackageKind { release.resolvedKind }
    public var capabilities: [String] { release.capabilities }

    public var isInstalled: Bool { engine.isInstalled() }
    public var installedVersion: SemanticVersion? { engine.installedVersion() }

    public var hasUpdate: Bool {
        guard let installed = installedVersion, let remote = release.semanticVersion else {
            return false
        }
        return installed < remote
    }
}

/// Turns the signed manifest into installable packages. Pure and
/// synchronous so the arch/macOS filtering is testable without network.
public enum EnginePackageCatalog {
    public static func packages(
        from manifest: EngineReleaseManifest,
        compatibleArchitectures: [String] = EngineReleaseManifest.compatibleArchitectures,
        macOS: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> [EnginePackage] {
        manifest.latestReleases(
            compatibleArchitectures: compatibleArchitectures,
            macOS: macOS
        ).map { release in
            EnginePackage(
                release: release,
                engine: WineEngineCatalog.engine(for: release)
            )
        }
    }

    /// Network failures are intentionally silent: an offline launch keeps
    /// the built-in catalog and the setup flow's pinned fallback.
    public static func load(
        loader: EngineManifestLoader = EngineManifestLoader(),
        publicKeyBase64: String? = EngineManifestLoader.bundledPublicKey()
    ) async -> [EnginePackage] {
        guard let manifest = try? await loader.load(publicKeyBase64: publicKeyBase64) else {
            return []
        }
        return packages(from: manifest)
    }

    public static func package(
        engineID: String,
        loader: EngineManifestLoader = EngineManifestLoader(),
        publicKeyBase64: String? = EngineManifestLoader.bundledPublicKey()
    ) async -> EnginePackage? {
        await load(loader: loader, publicKeyBase64: publicKeyBase64)
            .first { $0.id == engineID }
    }
}

/// Downloads a signed engine package, verifies its digest, and hands it
/// to the import path named by the manifest. This is the only installer
/// the UI needs for manifest-described engines; adding an engine is a
/// manifest entry, not a new Swift branch.
public enum EnginePackageInstaller {
    @discardableResult
    public static func install(
        _ package: EnginePackage,
        downloadService: EngineDownloadService = .shared,
        onProgress: (@Sendable (EngineDownloadProgress) -> Void)? = nil
    ) async throws -> LocalPathEngine {
        let release = package.release
        let fileManager = FileManager.default
        let pathExtension = release.url.pathExtension.isEmpty
            ? "archive"
            : release.url.pathExtension
        let archive = fileManager.temporaryDirectory
            .appending(path: "MacBottle-\(release.engineID)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        defer { try? fileManager.removeItem(at: archive) }

        try await downloadService.download(
            from: release.url,
            to: archive,
            expectedSHA256: release.sha256,
            onProgress: onProgress
        )

        let fallbackVersion = release.semanticVersion ?? SemanticVersion(0, 0, 0)
        switch release.resolvedInstallLayout {
        case .gcenxAppBundle:
            try await EngineImportService.importGcenxTarball(
                at: archive,
                engine: package.engine,
                fallbackVersion: fallbackVersion
            )
        case .wineRoot:
            try await EngineImportService.importTarball(
                at: archive,
                engine: package.engine,
                fallbackVersion: fallbackVersion
            )
        }

        guard package.engine.isInstalled() else {
            throw EngineImportError.unsupportedLayout(package.engine.libraryRoot)
        }
        Logger.wineKit.info(
            "EnginePackageInstaller: installed \(release.engineID) \(release.version)"
        )
        return package.engine
    }
}
