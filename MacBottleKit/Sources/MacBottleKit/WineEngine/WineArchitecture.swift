//
//  WineArchitecture.swift
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

/// The host (unix-side) architecture of a Wine engine build. Upstream
/// Wine on macOS places its compiled unix libraries under
/// `lib/wine/<arch>-unix`, so the directory present on disk identifies
/// the build. An engine may legitimately ship several (cross-compiled
/// WoW64 layouts), so detection returns the set.
public enum WineArchitecture: String, Sendable, CaseIterable {
    case x8664 = "x86_64"
    case aarch64

    public static let all: [WineArchitecture] = [.x8664, .aarch64]

    /// The `lib/wine/<arch>-unix` directory name for this architecture.
    public var unixDirectoryName: String {
        "\(rawValue)-unix"
    }

    /// Detect which architectures an engine root provides. The root is
    /// the engine's `libraryRoot` (containing `Wine/`).
    public static func available(in engineRoot: URL) -> [WineArchitecture] {
        WineArchitecture.all.filter { exists($0, in: engineRoot) }
    }

    public static func exists(_ architecture: WineArchitecture, in engineRoot: URL) -> Bool {
        let unixDir = engineRoot
            .appending(path: "Wine")
            .appending(path: "lib")
            .appending(path: "wine")
            .appending(path: architecture.unixDirectoryName)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: unixDir.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
