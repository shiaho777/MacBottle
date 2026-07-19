//
//  ContentStore.swift
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
import Darwin

public struct ContentStore: Sendable {
    public let root: URL

    public static func `default`() -> ContentStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier)
            .appending(path: "NativeCache")
        return ContentStore(root: base)
    }

    public init(root: URL) {
        self.root = root
    }

    public func steamClientVersionDir(_ version: String) -> URL {
        root.appending(path: "steam-client").appending(path: version)
    }

    public func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func materialize(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if clone(from: source, to: destination) {
            return
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    public func materializeTree(from sourceRoot: URL, to destinationRoot: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let rel = fileURL.path.replacingOccurrences(of: sourceRoot.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !rel.isEmpty else { continue }
            let dest = destinationRoot.appending(path: rel)
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                try materialize(from: fileURL, to: dest)
            }
        }
    }

    private func clone(from source: URL, to destination: URL) -> Bool {
        source.path.withCString { src in
            destination.path.withCString { dst in
                clonefile(src, dst, 0) == 0
            }
        }
    }
}
