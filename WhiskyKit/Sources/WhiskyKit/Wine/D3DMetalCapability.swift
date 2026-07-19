//
//  D3DMetalCapability.swift
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

public struct D3DMetalStatus: Sendable, Equatable {
    public let available: Bool
    public let frameworkURL: URL?
    public let sharedLibraryURL: URL?
    public let linkedUnixModules: Bool
    public let sourceDescription: String

    public var summary: String {
        if available && linkedUnixModules {
            return "D3DMetal ready"
        }
        if available {
            return "D3DMetal found (module bridge missing)"
        }
        return "D3DMetal not found"
    }
}

public enum D3DMetalCapability {
    private static let probeLock = NSLock()
    nonisolated(unsafe) private static var cachedProbeStatus: D3DMetalStatus?

    public static func probe(libraryRoot: URL = CrossOverEngine.default.libraryRoot) -> D3DMetalStatus {
        probeLock.lock()
        if let cachedProbeStatus {
            probeLock.unlock()
            return cachedProbeStatus
        }
        probeLock.unlock()
        let status = probeUncached(libraryRoot: libraryRoot)
        probeLock.lock()
        cachedProbeStatus = status
        probeLock.unlock()
        return status
    }

    private static func probeUncached(libraryRoot: URL) -> D3DMetalStatus {
        let candidates = candidateRoots(libraryRoot: libraryRoot)
        for root in candidates {
            let framework = root.appending(path: "D3DMetal.framework")
            let shared = root.appending(path: "libd3dshared.dylib")
            let frameworkExists = FileManager.default.fileExists(atPath: framework.path)
            let sharedExists = FileManager.default.fileExists(atPath: shared.path)
            if frameworkExists || sharedExists {
                let wineRoot = root.deletingLastPathComponent().deletingLastPathComponent()
                let linked = hasLinkedUnixModules(wineRoot: wineRoot)
                return D3DMetalStatus(
                    available: frameworkExists && sharedExists,
                    frameworkURL: frameworkExists ? framework : nil,
                    sharedLibraryURL: sharedExists ? shared : nil,
                    linkedUnixModules: linked,
                    sourceDescription: root.path
                )
            }
        }

        return D3DMetalStatus(
            available: false,
            frameworkURL: nil,
            sharedLibraryURL: nil,
            linkedUnixModules: false,
            sourceDescription: "none"
        )
    }

    @discardableResult
    public static func restoreBundledIfPossible(
        libraryRoot: URL = CrossOverEngine.default.libraryRoot
    ) throws -> D3DMetalStatus {
        let status = probe(libraryRoot: libraryRoot)
        if status.available {
            return status
        }

        let destination = libraryRoot
            .appending(path: "Wine")
            .appending(path: "lib")
            .appending(path: "external")
        let source = preferedBackupExternal()
        guard let source else {
            return status
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = ["D3DMetal.framework", "libd3dshared.dylib"]
        for item in items {
            let from = source.appending(path: item)
            let destinationItem = destination.appending(path: item)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            if FileManager.default.fileExists(atPath: destinationItem.path) {
                try FileManager.default.removeItem(at: destinationItem)
            }
            try FileManager.default.copyItem(at: from, to: destinationItem)
            Logger.wineKit.info("D3DMetalCapability restored \(item) from \(source.path)")
        }
        probeLock.lock()
        cachedProbeStatus = nil
        probeLock.unlock()
        return probe(libraryRoot: libraryRoot)
    }

    public static func environmentContributions(
        status: D3DMetalStatus,
        profile: RuntimeProfile,
        bottleDXVKEnabled: Bool
    ) -> [String: String] {
        guard status.available else { return [:] }
        guard profile == .modern64 || profile == .generic else { return [:] }
        guard !bottleDXVKEnabled else { return [:] }

        var env: [String: String] = [:]
        if let framework = status.frameworkURL {
            let parent = framework.deletingLastPathComponent().path
            env["DYLD_FALLBACK_LIBRARY_PATH"] = parent
            env["WINEDLLPATH"] = parent
        }
        env["D3DMETAL_FORCE_METAL"] = "1"
        env["ROSETTA_ADVERTISE_AVX"] = env["ROSETTA_ADVERTISE_AVX"] ?? "1"
        return env
    }

    private static func candidateRoots(libraryRoot: URL) -> [URL] {
        var roots: [URL] = [
            libraryRoot.appending(path: "Wine").appending(path: "lib").appending(path: "external"),
            WineEngineCatalog.d3dMetalLibraryRoot
                .appending(path: "Wine")
                .appending(path: "lib")
                .appending(path: "external")
        ]
        if let backup = preferedBackupExternal() {
            roots.append(backup)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = appSupport
            .appending(path: "com.isaacmarovitz.Whisky")
            .appending(path: "Libraries")
            .appending(path: "Wine")
            .appending(path: "lib")
            .appending(path: "external")
        roots.append(legacy)
        return roots
    }

    private static func preferedBackupExternal() -> URL? {
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
            let external = backup
                .appending(path: "Wine")
                .appending(path: "lib")
                .appending(path: "external")
            let framework = external.appending(path: "D3DMetal.framework")
            if FileManager.default.fileExists(atPath: framework.path) {
                return external
            }
        }
        return nil
    }

    private static func hasLinkedUnixModules(wineRoot: URL) -> Bool {
        let unix = wineRoot
            .appending(path: "lib")
            .appending(path: "wine")
            .appending(path: "x86_64-unix")
        let modules = ["d3d11.so", "d3d12.so", "d3d10.so"]
        return modules.contains {
            FileManager.default.fileExists(atPath: unix.appending(path: $0).path)
        }
    }
}
