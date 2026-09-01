//
//  EngineImportService.swift
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
import SemanticVersion
import os.log

public enum EngineImportError: LocalizedError {
    case unsupportedLayout(URL)
    case noArchitectureFound(URL)
    case tarballNotReadable(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLayout(let url):
            return String(
                format: String(localized: "engineImport.unsupportedLayout %@"),
                url.path(percentEncoded: false)
            )
        case .noArchitectureFound(let url):
            return String(
                format: String(localized: "engineImport.noArchitectureFound %@"),
                url.path(percentEncoded: false)
            )
        case .tarballNotReadable(let url):
            return String(
                format: String(localized: "engineImport.tarballNotReadable %@"),
                url.path(percentEncoded: false)
            )
        }
    }
}

/// Installs a user-provided Wine build (tarball or pre-expanded folder)
/// into a catalog-managed engine slot and validates the layout.
public enum EngineImportService {
    /// Validate that a candidate engine root contains a runnable Wine
    /// binary and at least one `<arch>-unix` module directory.
    @discardableResult
    public static func validate(engineRoot: URL) throws -> [WineArchitecture] {
        let wineBin = engineRoot
            .appending(path: "Wine")
            .appending(path: "bin")
        let wine64 = wineBin.appending(path: "wine64")
        let wine = wineBin.appending(path: "wine")
        let hasBinary = FileManager.default.isExecutableFile(atPath: wine64.path(percentEncoded: false))
            || FileManager.default.isExecutableFile(atPath: wine.path(percentEncoded: false))
        guard hasBinary else {
            throw EngineImportError.unsupportedLayout(engineRoot)
        }
        let architectures = WineArchitecture.available(in: engineRoot)
        guard !architectures.isEmpty else {
            throw EngineImportError.noArchitectureFound(engineRoot)
        }
        return architectures
    }

    /// Import a pre-expanded engine folder into `destination` by copy.
    /// Writes a `WhiskyWineVersion.plist` when the source lacks one —
    /// `isInstalled()` requires it, and stock upstream builds do not
    /// ship it.
    public static func importFolder(
        at source: URL,
        into destination: URL,
        fallbackVersion: SemanticVersion
    ) async throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw EngineImportError.tarballNotReadable(source)
        }

        let staging = destination.deletingLastPathComponent()
            .appending(path: "\(destination.lastPathComponent).staging-\(UUID().uuidString)")
        let trash = destination.deletingLastPathComponent()
            .appending(path: "\(destination.lastPathComponent).old-\(UUID().uuidString)")
        // The staging directory IS the future libraryRoot: copy the
        // source's *contents* into it, not the source folder itself.
        // copyItem(source → staging) would collide with the pre-created
        // staging or nest the tree one level too deep.
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let doImport: () async throws -> Void = {
            let contents = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil
            )
            for item in contents {
                let itemDestination = staging.appending(path: item.lastPathComponent)
                if fileManager.fileExists(atPath: itemDestination.path(percentEncoded: false)) {
                    try fileManager.removeItem(at: itemDestination)
                }
                try fileManager.copyItem(at: item, to: itemDestination)
            }
            let architectures = try validate(engineRoot: staging)
            await writeVersionPlistIfNeeded(
                engineRoot: staging,
                architectures: architectures,
                fallback: fallbackVersion
            )

            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.moveItem(at: destination, to: trash)
            }
            do {
                try fileManager.moveItem(at: staging, to: destination)
            } catch {
                if fileManager.fileExists(atPath: trash.path(percentEncoded: false)) {
                    try? fileManager.moveItem(at: trash, to: destination)
                }
                throw error
            }
            try? fileManager.removeItem(at: trash)
        }

        do {
            try await doImport()
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        Logger.wineKit.info("EngineImport: installed engine at \(destination.path)")
    }

    /// Import a tar.gz into `destination` via the engine's own install
    /// (untar), then validate the layout.
    public static func importTarball(
        at tarball: URL,
        engine: LocalPathEngine,
        fallbackVersion: SemanticVersion
    ) async throws {
        guard FileManager.default.isReadableFile(atPath: tarball.path(percentEncoded: false)) else {
            throw EngineImportError.tarballNotReadable(tarball)
        }
        try engine.install(from: tarball)
        let architectures = try validate(engineRoot: engine.libraryRoot)
        await writeVersionPlistIfNeeded(
            engineRoot: engine.libraryRoot,
            architectures: architectures,
            fallback: fallbackVersion
        )
        guard engine.isInstalled() else {
            throw EngineImportError.unsupportedLayout(engine.libraryRoot)
        }
    }

    private static func writeVersionPlistIfNeeded(
        engineRoot: URL,
        architectures: [WineArchitecture],
        fallback: SemanticVersion
    ) async {
        let plist = engineRoot.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        guard !FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)) else {
            return
        }
        // Probe `wine --version` (e.g. "wine-10.2") for an honest
        // version; fall back to the caller-supplied one otherwise.
        var version = fallback
        let binDir = engineRoot.appending(path: "Wine").appending(path: "bin")
        let wine64 = binDir.appending(path: "wine64")
        let binaryName = FileManager.default.isExecutableFile(
            atPath: wine64.path(percentEncoded: false)
        ) ? "wine64" : "wine"
        let wineBin = binDir.appending(path: binaryName)
        if let result = try? await ProcessRunner.run(executable: wineBin, arguments: ["--version"]) {
            let output = result.standardOutputString.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.hasPrefix("wine-") {
                let parts = output.dropFirst("wine-".count)
                    .split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count >= 2,
                   let major = Int(parts[0].prefix(while: \.isNumber)),
                   let minor = Int(parts[1].prefix(while: \.isNumber)) {
                    let patch = parts.count > 2 ? Int(parts[2].prefix(while: \.isNumber)) ?? 0 : 0
                    version = SemanticVersion(major, minor, patch)
                }
            }
        }
        _ = architectures
        if let data = try? PropertyListEncoder().encode(WhiskyWineVersion(version: version)) {
            try? data.write(to: plist)
        }
    }
}
