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

    public static var enginesRoot: URL {
        CrossOverEngine.applicationFolder.appending(path: "Engines")
    }

    public static var d3dMetalLibraryRoot: URL {
        enginesRoot.appending(path: d3dMetalIdentifier)
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

    public static func allEngines() -> [any WineEngine] {
        [modernEngine(), d3dMetalEngine()]
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
            parts.append("已安装")
        } else {
            parts.append("未安装")
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
        if fileManager.fileExists(atPath: destination.path) {
            let trash = enginesRoot.appending(path: "\(d3dMetalIdentifier).old-\(UUID().uuidString)")
            try fileManager.moveItem(at: destination, to: trash)
            try? fileManager.removeItem(at: trash)
        }
        try fileManager.moveItem(at: staging, to: destination)

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
            let d3d11 = backup
                .appending(path: "Wine")
                .appending(path: "lib")
                .appending(path: "wine")
                .appending(path: "x86_64-unix")
                .appending(path: "d3d11.so")
            let framework = backup
                .appending(path: "Wine")
                .appending(path: "lib")
                .appending(path: "external")
                .appending(path: "D3DMetal.framework")
            if FileManager.default.fileExists(atPath: wine64.path),
               FileManager.default.fileExists(atPath: d3d11.path),
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
            return "未找到带 D3DMetal 的 Wine 备份（Libraries.bak*）"
        case .engineNotInstalled:
            return "所选 Wine 引擎尚未安装"
        }
    }
}
