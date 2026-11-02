//
//  WineEngineCatalog.swift
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
import os.log

public enum WineEngineCatalog {
    public static let modernIdentifier = "crossover"
    public static let d3dMetalIdentifier = "crossover-d3dmetal"
    public static let arm64Identifier = "upstream-arm64"
    public static let gcenxIdentifier = "gcenx-wine"

    public static var enginesRoot: URL {
        CrossOverEngine.applicationFolder.appending(path: "Engines")
    }

    public static var d3dMetalLibraryRoot: URL {
        enginesRoot.appending(path: d3dMetalIdentifier)
    }

    public static var arm64LibraryRoot: URL {
        enginesRoot.appending(path: arm64Identifier)
    }

    public static var gcenxLibraryRoot: URL {
        enginesRoot.appending(path: gcenxIdentifier)
    }

    public static func modernEngine() -> CrossOverEngine {
        CrossOverEngine.default
    }

    public static func d3dMetalEngine() -> LocalPathEngine {
        LocalPathEngine(
            identifier: d3dMetalIdentifier,
            displayName: "CrossOver + D3DMetal",
            libraryRoot: d3dMetalLibraryRoot
        )
    }

    /// A user-imported native Apple Silicon Wine build. Not installed
    /// until the user imports one (Settings → engine → Import); a native
    /// aarch64 build removes the Rosetta translation layer entirely.
    public static func arm64Engine() -> LocalPathEngine {
        LocalPathEngine(
            identifier: arm64Identifier,
            displayName: "Upstream Wine (ARM64)",
            libraryRoot: arm64LibraryRoot
        )
    }

    /// Open-source x86_64 Wine build used as the offline fallback when
    /// the archived Whisky feed is unavailable. It runs under Rosetta on
    /// Apple Silicon and ships no D3DMetal/DXVK, so it is a baseline,
    /// not a replacement for the CrossOver engine.
    public static func gcenxEngine() -> LocalPathEngine {
        LocalPathEngine(
            identifier: gcenxIdentifier,
            displayName: "Wine 11.21 (Gcenx, x86_64)",
            libraryRoot: gcenxLibraryRoot
        )
    }

    public static func allEngines() -> [any WineEngine] {
        var engines: [any WineEngine] = [
            modernEngine(),
            d3dMetalEngine(),
            gcenxEngine(),
            arm64Engine()
        ]
        engines.append(contentsOf: discoveredEngines())
        return engines
    }

    /// Any engine folder dropped under `Engines/` that passes the same
    /// layout validation as a user import. The three built-in slots stay
    /// first; discovered builds follow in name order.
    public static func discoveredEngines(in root: URL? = nil) -> [any WineEngine] {
        let root = root ?? enginesRoot
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let reserved = Set([modernIdentifier, d3dMetalIdentifier, arm64Identifier, gcenxIdentifier])
        return contents
            .filter { url in
                let name = url.lastPathComponent
                guard !reserved.contains(name),
                      !name.contains(".staging-"),
                      !name.contains(".old-") else {
                    return false
                }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      (try? EngineImportService.validate(engineRoot: url)) != nil else {
                    return false
                }
                return LocalPathEngine(
                    identifier: name,
                    displayName: name,
                    libraryRoot: url
                ).installedVersion() != nil
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                LocalPathEngine(
                    identifier: url.lastPathComponent,
                    displayName: url.lastPathComponent,
                    libraryRoot: url
                )
            }
    }

    public static func engine(id: String) -> (any WineEngine)? {
        allEngines().first { $0.identifier == id }
    }

    public static func describe(_ engine: any WineEngine) -> String {
        var parts: [String] = [engine.displayName]
        if let version = engine.installedVersion() {
            parts.append("v\(version.major).\(version.minor).\(version.patch)")
        }
        if engine.isInstalled() {
            parts.append(String(localized: "engineCatalog.installed"))
        } else {
            parts.append(String(localized: "engineCatalog.notInstalled"))
        }
        if let local = engine as? LocalPathEngine, local.supportsD3DMetalBridge {
            parts.append("D3DMetal")
        } else if engine.identifier == modernIdentifier {
            let status = D3DMetalCapability.probe(libraryRoot: engine.libraryRoot)
            if status.available && status.linkedUnixModules {
                parts.append("D3DMetal")
            }
        }
        return parts.joined(separator: " · ")
    }

    @discardableResult
    public static func ensureD3DMetalEngine(force: Bool = false) throws -> LocalPathEngine {
        let engine = d3dMetalEngine()
        if engine.isInstalled(), engine.supportsD3DMetalBridge, !force {
            return engine
        }

        guard let source = preferredBackupLibraries() else {
            throw WineEngineCatalogError.backupNotFound
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: enginesRoot, withIntermediateDirectories: true)

        let staging = enginesRoot.appending(path: "\(d3dMetalIdentifier).staging-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }

        try copyTree(from: source, to: staging)

        let destination = d3dMetalLibraryRoot
        let trash = enginesRoot.appending(path: "\(d3dMetalIdentifier).old-\(UUID().uuidString)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: trash)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            // Put the previous engine back rather than leaving the
            // machine with no engine installed at all.
            if fileManager.fileExists(atPath: trash.path) {
                try? fileManager.moveItem(at: trash, to: destination)
            }
            throw error
        }
        try? fileManager.removeItem(at: trash)

        Logger.wineKit.info("WineEngineCatalog installed D3DMetal engine at \(destination.path)")
        return d3dMetalEngine()
    }

    public static func preferredBackupLibraries() -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = appSupport.appending(path: Bundle.whiskyBundleIdentifier)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix("Libraries.bak") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for backup in backups {
            let wine64 = backup.appending(path: "Wine").appending(path: "bin").appending(path: "wine64")
            let framework = backup
                .appending(path: "Wine")
                .appending(path: "lib")
                .appending(path: "external")
                .appending(path: "D3DMetal.framework")
            let hasD3D11 = WineArchitecture.all.contains { architecture in
                let unix = backup
                    .appending(path: "Wine")
                    .appending(path: "lib")
                    .appending(path: "wine")
                    .appending(path: architecture.unixDirectoryName)
                return FileManager.default.fileExists(
                    atPath: unix.appending(path: "d3d11.so").path
                )
            }
            if FileManager.default.fileExists(atPath: wine64.path),
               hasD3D11,
               FileManager.default.fileExists(atPath: framework.path) {
                return backup
            }
        }

        let legacy = appSupport
            .appending(path: "com.isaacmarovitz.Whisky")
            .appending(path: "Libraries")
        let legacyWine = legacy.appending(path: "Wine").appending(path: "bin").appending(path: "wine64")
        let legacyD3D = legacy
            .appending(path: "Wine")
            .appending(path: "lib")
            .appending(path: "external")
            .appending(path: "D3DMetal.framework")
        if FileManager.default.fileExists(atPath: legacyWine.path),
           FileManager.default.fileExists(atPath: legacyD3D.path) {
            return legacy
        }

        return nil
    }

    private static func copyTree(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}

public enum WineEngineCatalogError: LocalizedError {
    case backupNotFound
    case engineNotInstalled

    public var errorDescription: String? {
        switch self {
        case .backupNotFound:
            return String(localized: "engineCatalog.d3dmetalBackupMissing")
        case .engineNotInstalled:
            return String(localized: "engineCatalog.engineNotInstalled")
        }
    }
}
