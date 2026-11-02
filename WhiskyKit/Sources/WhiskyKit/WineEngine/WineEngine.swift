//
//  WineEngine.swift
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
import CryptoKit
import SemanticVersion

// MARK: - WineEngine

/// The Wine flavour that MacBottle uses at runtime.
///
/// Different flavours (CrossOver-derived, pure upstream Wine, Apple GPTK)
/// differ in where their binaries live on disk, how they are installed or
/// updated, and what licence terms apply to redistributing them. The
/// `WineEngine` protocol captures only the minimum surface the rest of
/// MacBottle needs; concrete engines can add their own capabilities
/// without leaking into callers.
///
/// Engines are intentionally stateless from the app's point of view: all
/// state (installed version, disk paths) is computed from the engine's
/// `libraryRoot` on demand. This keeps substitution easy and makes unit
/// testing trivial — a fake engine pointing at a temp directory is enough.
public protocol WineEngine: Sendable {
    /// Stable machine identifier for this engine flavour. Used as a disk
    /// segment under `Application Support/<bundleID>/Engines/<identifier>/`
    /// so multiple flavours can coexist without clobbering each other.
    ///
    /// Examples: `crossover`, `upstream`, `gptk2`.
    var identifier: String { get }

    /// Human-readable name shown in the UI.
    var displayName: String { get }

    /// Where this engine installs its `bin/`, `lib/`, and version file.
    var libraryRoot: URL { get }

    /// Absolute path to the `wine64` (or equivalent) binary. May point to
    /// a file that does not yet exist if the engine has not been installed.
    var wineBinary: URL { get }

    /// Absolute path to the `wineserver` binary.
    var wineserverBinary: URL { get }

    /// Folder containing DXVK DLLs this engine ships with, or an empty
    /// folder if this engine does not package DXVK.
    var dxvkFolder: URL { get }

    /// Whether the engine is installed and usable right now.
    func isInstalled() -> Bool

    /// Reports the installed version if one can be determined.
    func installedVersion() -> SemanticVersion?

    /// Install the engine from a tarball URL produced by the engine's
    /// release channel. The tarball is deleted after successful extraction.
    func install(from tarball: URL) throws

    /// Remove the engine's installed files from disk. Bottles created
    /// against the engine are untouched.
    func uninstall() throws

    /// Check the engine's release feed for a newer version. Returns the
    /// latest remote version and whether it is strictly newer than the
    /// local one. Network failures surface as `(false, local ?? 0.0.0)`.
    func checkForUpdate() async -> (hasUpdate: Bool, remoteVersion: SemanticVersion)
}

// MARK: - Defaults

public extension WineEngine {
    /// Convenience that combines `isInstalled` and `installedVersion` in
    /// the pattern UI setup views use.
    func installedOrNil() -> SemanticVersion? {
        isInstalled() ? installedVersion() : nil
    }

    /// Whether this engine actually packages DXVK. A locally imported
    /// upstream build often does not, and installing
    /// `WINEDLLOVERRIDES` for DLLs that are not there breaks launches.
    var supportsDXVK: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: dxvkFolder.path(percentEncoded: false))
            && (fileManager.fileExists(
                atPath: dxvkFolder.appending(path: "x64").path(percentEncoded: false)
            ) || fileManager.fileExists(
                atPath: dxvkFolder.appending(path: "x32").path(percentEncoded: false)
            ))
    }

    /// Verify a downloaded engine archive against an expected digest
    /// before handing it to the (destructive) install path. Callers that
    /// have a manifest should always use this overload.
    func install(from tarball: URL, expectedSHA256: String) throws {
        let actual = ChunkedDownloader.sha256Hex(of: tarball)
        guard !actual.isEmpty else {
            throw WineEngineIntegrityError.unreadable(tarball)
        }
        guard actual == expectedSHA256.lowercased() else {
            throw WineEngineIntegrityError.checksumMismatch(
                expected: expectedSHA256,
                actual: actual
            )
        }
        try install(from: tarball)
    }
}

public enum WineEngineIntegrityError: Error, LocalizedError {
    case unreadable(URL)
    case checksumMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return "Could not read the engine archive at \(url.path)."
        case .checksumMismatch(let expected, let actual):
            return "Engine archive failed integrity verification (expected \(expected), got \(actual))."
        }
    }
}
