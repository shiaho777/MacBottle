//
//  InstallerStaging.swift
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

import Foundation

public enum InstallerStaging {
    public static let stagingFolderName = "MacBottleImports"

    /// Copy an installer into the bottle so Wine can see it under a
    /// stable `C:` path. Files that already live inside the bottle are
    /// returned unchanged; non-ASCII names are replaced because the
    /// Windows installer sees the path through Wine's ANSI APIs.
    public static func stage(_ url: URL, inBottle bottleURL: URL) throws -> URL {
        let standardizedBottle = bottleURL.standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(standardizedBottle) {
            return url
        }

        let staging = bottleURL
            .appending(path: "drive_c")
            .appending(path: stagingFolderName)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        var name = url.lastPathComponent
        if name.unicodeScalars.contains(where: { !$0.isASCII }) {
            let ext = url.pathExtension
            name = "installer_\(Int(Date().timeIntervalSince1970))"
            if !ext.isEmpty {
                name += ".\(ext)"
            }
        }

        let destination = staging.appending(path: name)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
