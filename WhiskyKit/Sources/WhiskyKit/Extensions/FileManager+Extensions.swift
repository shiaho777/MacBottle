//
//  FileManager+Extensions.swift
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

extension FileManager {
    func replaceDLLs(
        in destinationDirectory: URL, withContentsIn sourceDirectory: URL, makeOriginalCopy: Bool = false
    ) throws {
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "dll" else { continue }
            let originalURL = destinationDirectory.appending(path: fileURL.lastPathComponent)
            try FileManager.default.replaceFile(at: originalURL, with: fileURL, makeOriginalCopy: makeOriginalCopy)
        }
    }

    func replaceFile(at originalURL: URL, with replacementURL: URL, makeOriginalCopy: Bool = true) throws {
        let originalPath = originalURL.path(percentEncoded: false)
        let replacementPath = replacementURL.path(percentEncoded: false)
        guard fileExists(atPath: replacementPath) else { return }

        if fileExists(atPath: originalPath) {
            if makeOriginalCopy {
                let copyURL = originalURL.appendingPathExtension("orig")
                let copyPath = copyURL.path(percentEncoded: false)
                if fileExists(atPath: copyPath), filesLikelyIdentical(originalURL, replacementURL) {
                    return
                }
                if fileExists(atPath: copyPath) {
                    try FileManager.default.removeItem(at: copyURL)
                }
                try FileManager.default.moveItem(at: originalURL, to: copyURL)
            } else if filesLikelyIdentical(originalURL, replacementURL) {
                return
            } else {
                try FileManager.default.removeItem(at: originalURL)
            }
            try FileManager.default.copyItem(at: replacementURL, to: originalURL)
            return
        }

        try FileManager.default.copyItem(at: replacementURL, to: originalURL)
    }

    private func filesLikelyIdentical(_ lhs: URL, _ rhs: URL) -> Bool {
        guard
            let left = try? attributesOfItem(atPath: lhs.path(percentEncoded: false)),
            let right = try? attributesOfItem(atPath: rhs.path(percentEncoded: false)),
            let leftSize = left[.size] as? NSNumber,
            let rightSize = right[.size] as? NSNumber
        else {
            return false
        }
        return leftSize == rightSize
    }
}
