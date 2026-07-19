//
//  CrossOverEngine.swift
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

/// `WineEngine` backed by a CrossOver-derived Wine build packaged by the
/// upstream Whisky project. This is the default engine inherited from the
/// fork parent and the only engine shipped in v0.1.
///
/// Disk layout (created on install):
///
///     Application Support/<bundleID>/Libraries/
///       Wine/
///         bin/wine64
///         bin/wineserver
///       DXVK/
///       WhiskyWineVersion.plist
///
/// The `applicationFolder` intentionally lives under the running app's
/// bundle identifier rather than under a literal "Whisky" segment so a
/// MacBottle install writes into `app.macbottle.MacBottle/...` while a
/// side-by-side legacy Whisky install stays isolated.
public struct CrossOverEngine: WineEngine {
    public static let `default` = CrossOverEngine()

    public let identifier = "crossover"
    public let displayName = "CrossOver Wine (Whisky build)"

    /// URL the installer polls for the current remote version. Kept as a
    /// property so tests and future engine subclasses can override.
    public let updateFeedURL: URL

    public init(updateFeedURL: URL = Self.defaultUpdateFeedURL) {
        self.updateFeedURL = updateFeedURL
    }

    public static let defaultUpdateFeedURL: URL = {
        guard let url = URL(string: "https://data.getwhisky.app/Wine/WhiskyWineVersion.plist") else {
            fatalError("CrossOverEngine.defaultUpdateFeedURL: hardcoded URL failed to parse")
        }
        return url
    }()

    // MARK: - Disk layout

    /// `~/Library/Application Support/<bundleID>`.
    public static var applicationFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier)
    }

    public var libraryRoot: URL {
        Self.applicationFolder.appending(path: "Libraries")
    }

    public var binFolder: URL {
        libraryRoot.appending(path: "Wine").appending(path: "bin")
    }

    public var wineBinary: URL {
        let wine64 = binFolder.appending(path: "wine64")
        if FileManager.default.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return binFolder.appending(path: "wine")
    }

    public var wineserverBinary: URL {
        binFolder.appending(path: "wineserver")
    }

    public var dxvkFolder: URL {
        libraryRoot.appending(path: "DXVK")
    }

    private var versionPlistURL: URL {
        libraryRoot.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
    }

    // MARK: - WineEngine

    public func isInstalled() -> Bool {
        installedVersion() != nil
    }

    public func installedVersion() -> SemanticVersion? {
        do {
            let data = try Data(contentsOf: versionPlistURL)
            let info = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
            return info.version
        } catch {
            return nil
        }
    }

    public func install(from tarball: URL) throws {
        let fileManager = FileManager.default
        let appFolder = Self.applicationFolder

        try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: libraryRoot.path) {
            try fileManager.removeItem(at: libraryRoot)
        }

        try Tar.untar(tarBall: tarball, toURL: appFolder)
        try fileManager.removeItem(at: tarball)
    }

    public func uninstall() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: libraryRoot.path) else { return }
        try fileManager.removeItem(at: libraryRoot)
    }

    public func checkForUpdate() async -> (hasUpdate: Bool, remoteVersion: SemanticVersion) {
        let local = installedVersion() ?? SemanticVersion(0, 0, 0)

        guard let remote = await fetchRemoteVersion() else {
            return (false, local)
        }
        return (local < remote, remote)
    }

    private func fetchRemoteVersion() async -> SemanticVersion? {
        await withCheckedContinuation { continuation in
            let session = URLSession(configuration: .ephemeral)
            let task = session.dataTask(with: URLRequest(url: updateFeedURL)) { data, _, error in
                if let error {
                    Logger.wineKit.debug("CrossOverEngine: update check failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let info = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
                    continuation.resume(returning: info.version)
                } catch {
                    Logger.wineKit.debug("CrossOverEngine: update decode failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
            task.resume()
        }
    }
}
