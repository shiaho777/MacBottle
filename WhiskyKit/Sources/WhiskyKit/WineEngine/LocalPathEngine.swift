//
//  LocalPathEngine.swift
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

public struct LocalPathEngine: WineEngine, Sendable, Equatable {
    public let identifier: String
    public let displayName: String
    public let libraryRoot: URL

    public init(identifier: String, displayName: String, libraryRoot: URL) {
        self.identifier = identifier
        self.displayName = displayName
        self.libraryRoot = libraryRoot
    }

    public var wineBinary: URL {
        let wine64 = libraryRoot.appending(path: "Wine").appending(path: "bin").appending(path: "wine64")
        if FileManager.default.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return libraryRoot.appending(path: "Wine").appending(path: "bin").appending(path: "wine")
    }

    public var wineserverBinary: URL {
        libraryRoot.appending(path: "Wine").appending(path: "bin").appending(path: "wineserver")
    }

    public var dxvkFolder: URL {
        libraryRoot.appending(path: "DXVK")
    }

    private var versionPlistURL: URL {
        libraryRoot.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
    }

    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: wineBinary.path(percentEncoded: false))
    }

    public func installedVersion() -> SemanticVersion? {
        if let data = try? Data(contentsOf: versionPlistURL),
           let info = try? PropertyListDecoder().decode(WhiskyWineVersion.self, from: data) {
            return info.version
        }
        return nil
    }

    public func install(from tarball: URL) throws {
        let parent = libraryRoot.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: libraryRoot.path) {
            try FileManager.default.removeItem(at: libraryRoot)
        }
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Tar.untar(tarBall: tarball, toURL: libraryRoot)
        try FileManager.default.removeItem(at: tarball)
    }

    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: libraryRoot.path) else { return }
        try FileManager.default.removeItem(at: libraryRoot)
    }

    public func checkForUpdate() async -> (hasUpdate: Bool, remoteVersion: SemanticVersion) {
        let local = installedVersion() ?? SemanticVersion(0, 0, 0)
        return (false, local)
    }

    public var supportsD3DMetalBridge: Bool {
        let unix = libraryRoot
            .appending(path: "Wine")
            .appending(path: "lib")
            .appending(path: "wine")
            .appending(path: "x86_64-unix")
        let d3d11 = unix.appending(path: "d3d11.so")
        let external = libraryRoot
            .appending(path: "Wine")
            .appending(path: "lib")
            .appending(path: "external")
            .appending(path: "D3DMetal.framework")
        return FileManager.default.fileExists(atPath: d3d11.path)
            && FileManager.default.fileExists(atPath: external.path)
    }
}
