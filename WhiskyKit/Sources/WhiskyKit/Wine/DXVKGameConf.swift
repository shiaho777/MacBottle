//
//  DXVKGameConf.swift
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
import os.log

/// Writers for the per-game `dxvk.conf` DXVK reads next to the
/// executable (documented precedence: `<exe>.conf` in the game folder,
/// then `%DXVK_CONFIG_FILE%`, then the global file).
///
/// The two levers with real frame-rate leverage on UMA Apple Silicon:
///
/// - **Frame latency.** `dxgi.maxFrameLatency`/`d3d9.maxFrameLatency`
///   default to a deep queue; a queued-frame pipeline adds display
///   latency and smooths over, but never raises, the throughput
///   ceiling — while a deep queue burns UMA bandwidth on frames nobody
///   will see. Pinning 1 ties presentation to input.
/// - **VRAM reporting.** Wine's UMA reporting confuses DXGI's memory
///   residency heuristics; `dxgi.maxDeviceMemory`/`maxSharedMemory`
///   give the title an honest budget so it stops thrash-evicting.
///
/// Everything written here is idempotent and reversible: the writer
/// snapshots the prior file bytes on first write so a posture change
/// or uninstall restores exactly what was there.
public enum DXVKGameConf {
    public struct Posture: Sendable, Equatable {
        public var maxFrameLatency: Int
        public var maxDeviceMemoryMegabytes: Int

        public init(maxFrameLatency: Int, maxDeviceMemoryMegabytes: Int) {
            self.maxFrameLatency = maxFrameLatency
            self.maxDeviceMemoryMegabytes = maxDeviceMemoryMegabytes
        }

        /// Latency-first posture: queue depth 1, honest UMA budget
        /// (~2/3 of physical RAM, clamped to 8–24 GB).
        public static func responsive(physicalMemoryBytes: UInt64) -> Posture {
            Posture(
                maxFrameLatency: 1,
                maxDeviceMemoryMegabytes: min(
                    max(Int(physicalMemoryBytes * 2 / 3 / 1_000_000), 8_192),
                    24_000
                )
            )
        }
    }

    static func confURL(executable: URL) -> URL {
        executable.deletingLastPathComponent()
            .appending(component: executable.lastPathComponent + ".conf")
    }

    static func lines(for posture: Posture) -> [String] {
        [
            "dxgi.maxFrameLatency = \(posture.maxFrameLatency)",
            "d3d9.maxFrameLatency = \(posture.maxFrameLatency)",
            "dxgi.maxDeviceMemory = \(posture.maxDeviceMemoryMegabytes)",
            "dxgi.maxSharedMemory = \(posture.maxDeviceMemoryMegabytes)"
        ]
    }

    @discardableResult
    public static func apply(
        posture: Posture,
        executable: URL
    ) -> Bool {
        let url = confURL(executable: executable)
        let fileManager = FileManager.default
        let desired = lines(for: posture)

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if desired.allSatisfy({ existing.contains($0) }) {
            return false
        }
        // First managed write over a pre-existing file (perhaps a
        // user-authored conf): snapshot the original bytes so removal
        // restores them byte-for-byte.
        let snapshotURL = url.appendingPathExtension("macbottle.orig")
        if !existing.isEmpty,
           !fileManager.fileExists(atPath: snapshotURL.path(percentEncoded: false)),
           let original = fileManager.contents(atPath: url.path(percentEncoded: false)) {
            try? original.write(to: snapshotURL)
        }

        var merged = existing
        for line in desired {
            let key = line.split(separator: " ").first.map(String.init) ?? line
            merged = upsertLine(in: merged, key: key, line: line)
        }
        do {
            try merged.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Logger.wineKit.error("DXVKGameConf write failed: \(error.localizedDescription)")
            return false
        }
    }

    public static func remove(executable: URL) {
        let url = confURL(executable: executable)
        let fileManager = FileManager.default
        let snapshotURL = url.appendingPathExtension("macbottle.orig")
        if let original = try? Data(contentsOf: snapshotURL) {
            try? original.write(to: url)
            try? fileManager.removeItem(at: snapshotURL)
        } else {
            try? fileManager.removeItem(at: url)
        }
    }

    static func upsertLine(in text: String, key: String, line: String) -> String {
        // A '#' comment (DXVK's shipped defaults) is not a setting:
        // upsert replaces the live line and strips the commented
        // sibling so the file states one truth per key.
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let liveRegex = try? NSRegularExpression(
            pattern: "^(\(escaped))\\s*=.*$",
            options: .anchorsMatchLines
        ), let commentRegex = try? NSRegularExpression(
            pattern: "^#\\s*\(escaped)\\s*=.*$",
            options: .anchorsMatchLines
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        if let match = liveRegex.firstMatch(in: result, options: [], range: range),
           let matchRange = Range(match.range, in: result) {
            result.replaceSubrange(matchRange, with: line)
        } else {
            if !result.isEmpty, !result.hasSuffix("\n") {
                result += "\n"
            }
            result += line + "\n"
        }
        let postRange = NSRange(result.startIndex..<result.endIndex, in: result)
        if let commentMatch = commentRegex.firstMatch(in: result, options: [], range: postRange),
           let commentLine = Range(commentMatch.range, in: result) {
            result.removeSubrange(commentLine)
        }
        return result
    }
}
