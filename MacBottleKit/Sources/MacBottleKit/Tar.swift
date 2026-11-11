//
//  Tar.swift
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

import Darwin
import Foundation

public enum TarError: Error, LocalizedError {
    case listingFailed(String)
    case extractionFailed(String)
    case creationFailed(String)
    case absolutePath(String)
    case pathTraversal(String)
    case symlinkEscape(String)

    public var errorDescription: String? {
        switch self {
        case .listingFailed(let output):
            return "Could not list archive: \(output)"
        case .extractionFailed(let output):
            return "Could not extract archive: \(output)"
        case .creationFailed(let output):
            return "Could not create archive: \(output)"
        case .absolutePath(let path):
            return "Archive contains an absolute path: \(path)"
        case .pathTraversal(let path):
            return "Archive contains a path traversal entry: \(path)"
        case .symlinkEscape(let path):
            return "Archive entry resolves outside the extraction root: \(path)"
        }
    }
}

public class Tar {
    static let tarBinary: URL = URL(fileURLWithPath: "/usr/bin/tar")

    public static func tar(folder: URL, toURL: URL) throws {
        // Archive the folder itself, not its absolute path. Passing an
        // absolute path produces entries like `Users/.../folder`, which
        // extract into a nested tree instead of the destination.
        let parent = folder.deletingLastPathComponent()
        let result = try run(["-zcf", toURL.path, "-C", parent.path, folder.lastPathComponent])
        guard result.status == 0 else {
            throw TarError.creationFailed(result.error)
        }
    }

    public static func untar(tarBall: URL, toURL: URL) throws {
        let entries = try list(tarBall)
        for entry in entries {
            try validate(entry: entry)
        }

        let fileManager = FileManager.default
        let staging = toURL
            .deletingLastPathComponent()
            .appending(path: ".untar-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let result = try run(["-xf", tarBall.path, "-C", staging.path])
        guard result.status == 0 else {
            throw TarError.extractionFailed(result.error)
        }

        try validateTree(at: staging)
        try mergeContents(from: staging, into: toURL)
    }

    // MARK: - Safety

    static func list(_ tarBall: URL) throws -> [String] {
        let result = try run(["-tf", tarBall.path])
        guard result.status == 0 else {
            throw TarError.listingFailed(result.error)
        }
        return result.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    static func validate(entry: String) throws {
        guard !entry.hasPrefix("/") else {
            throw TarError.absolutePath(entry)
        }
        let components = entry.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            throw TarError.pathTraversal(entry)
        }
        guard !entry.contains("\0") else {
            throw TarError.pathTraversal(entry)
        }
    }

    /// Resolve every extracted item and reject anything that escapes the
    /// staging root. This catches symlinks that point outside even when
    /// the entry names themselves are clean.
    static func validateTree(at root: URL) throws {
        guard let rootPath = canonicalPath(root) else {
            throw TarError.extractionFailed("could not resolve extraction root")
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return }

        for case let item as URL in enumerator {
            guard let path = canonicalPath(item) else {
                throw TarError.symlinkEscape(item.lastPathComponent)
            }
            guard path == rootPath || path.hasPrefix(rootPath + "/") else {
                throw TarError.symlinkEscape(item.lastPathComponent)
            }
        }
    }

    /// `realpath(3)` resolves `/var` → `/private/var` consistently;
    /// `URL.resolvingSymlinksInPath()` does not, which made the prefix
    /// check fail on macOS temporary directories.
    private static func canonicalPath(_ url: URL) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path(percentEncoded: false), &buffer) != nil else {
            return nil
        }
        return String(cString: buffer)
    }

    static func mergeContents(from staging: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: nil
        )
        let trash = destination
            .deletingLastPathComponent()
            .appending(path: ".untar-old-\(UUID().uuidString)")
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: trash) }

        var moved: [(target: URL, backup: URL?)] = []
        do {
            for item in contents {
                let target = destination.appending(path: item.lastPathComponent)
                var backup: URL?
                if fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
                    let old = trash.appending(path: item.lastPathComponent)
                    try fileManager.moveItem(at: target, to: old)
                    backup = old
                }
                try fileManager.moveItem(at: item, to: target)
                moved.append((target: target, backup: backup))
            }
        } catch {
            for entry in moved.reversed() {
                if let backup = entry.backup {
                    try? fileManager.removeItem(at: entry.target)
                    try? fileManager.moveItem(at: backup, to: entry.target)
                } else {
                    try? fileManager.removeItem(at: entry.target)
                }
            }
            throw error
        }
    }

    private struct ToolResult {
        let status: Int32
        let output: String
        let error: String
    }

    private static func run(_ arguments: [String]) throws -> ToolResult {
        let result = try ProcessRunner.runSync(
            executable: tarBinary,
            arguments: arguments,
            timeout: .seconds(600)
        )

        return ToolResult(
            status: result.exitCode,
            output: result.standardOutputString,
            error: result.standardErrorString
        )
    }
}
