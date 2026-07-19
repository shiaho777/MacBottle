//
//  DepotStore.swift
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

public struct DepotStore: Sendable {
    public let contentStore: ContentStore

    public init(contentStore: ContentStore = .default()) {
        self.contentStore = contentStore
    }

    public var steamCMDRoot: URL {
        contentStore.root.appending(path: "steamcmd")
    }

    public func depotRoot(appID: Int) -> URL {
        contentStore.root
            .appending(path: "depots")
            .appending(path: String(appID))
    }

    public func libraryRoot(appID: Int) -> URL {
        depotRoot(appID: appID).appending(path: "steam")
    }

    public func steamapps(appID: Int) -> URL {
        libraryRoot(appID: appID).appending(path: "steamapps")
    }

    public func bottleSteamRoot(bottleURL: URL) -> URL {
        bottleURL
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
    }

    public func bottleSteamapps(bottleURL: URL) -> URL {
        bottleSteamRoot(bottleURL: bottleURL).appending(path: "steamapps")
    }

    public func isDepotPresent(appID: Int) -> Bool {
        let steamapps = steamapps(appID: appID)
        let manifest = steamapps.appending(path: "appmanifest_\(appID).acf")
        if FileManager.default.fileExists(atPath: manifest.path) {
            return true
        }
        let common = steamapps.appending(path: "common")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: common.path) else {
            return false
        }
        return !items.isEmpty
    }

    public func materializeDepot(appID: Int, intoBottle bottleURL: URL) throws {
        let sourceSteamapps = steamapps(appID: appID)
        guard FileManager.default.fileExists(atPath: sourceSteamapps.path) else {
            throw DepotStoreError.depotMissing(appID)
        }
        let destSteam = bottleSteamRoot(bottleURL: bottleURL)
        let destSteamapps = bottleSteamapps(bottleURL: bottleURL)
        try contentStore.ensureDir(destSteam)
        try contentStore.ensureDir(destSteamapps)

        try mergeTree(from: sourceSteamapps, to: destSteamapps)

        let stamp = destSteam.appending(path: ".macbottle_depot_\(appID)")
        try """
        appid=\(appID)
        materialized=\(ISO8601DateFormatter().string(from: Date()))
        source=\(sourceSteamapps.path)
        """.write(to: stamp, atomically: true, encoding: .utf8)
    }

    private func mergeTree(from sourceRoot: URL, to destinationRoot: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let relative = fileURL.path
                .replacingOccurrences(of: sourceRoot.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            let destination = destinationRoot.appending(path: relative)
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                try contentStore.materialize(from: fileURL, to: destination)
            }
        }
    }
}

public enum DepotStoreError: Error, LocalizedError {
    case depotMissing(Int)

    public var errorDescription: String? {
        switch self {
        case .depotMissing(let appID):
            return "Depot for app \(appID) is not present in the native cache."
        }
    }
}
