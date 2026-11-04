//
//  WinePath.swift
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

public enum WinePath {
    /// Translate a host path inside a bottle's `drive_c` to the `C:\`
    /// path Wine reports. Paths outside the bottle are passed through
    /// with Windows separators so they still render readably.
    public static func windowsPath(for fileURL: URL, inBottle bottleURL: URL) -> String {
        let driveC = bottleURL.appending(path: "drive_c").standardizedFileURL.path
        let full = fileURL.standardizedFileURL.path
        guard full == driveC || full.hasPrefix(driveC + "/") else {
            return full.replacingOccurrences(of: "/", with: "\\")
        }

        let relative = String(full.dropFirst(driveC.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return "C:\\" }
        return "C:\\" + relative.replacingOccurrences(of: "/", with: "\\")
    }
}
