//
//  PrefixReadinessOracle.swift
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

/// Predicts, from cheap on-disk evidence, whether a Wine prefix is
/// boot-complete — without spawning `wineboot` (10–15 s) or any wine
/// process at all.
///
/// The oracle is the heart of the ZeroPath launch path. Wine itself
/// answers "is this prefix updated?" by comparing the mtime of
/// `.update-timestamp` against the installed wine build, then running a
/// full `wineboot -u` when in doubt. All of that is serialized behind a
/// wineserver round-trip the user waits on. The oracle instead reads a
/// constant-size tuple of prefix state —
/// `.update-timestamp` mtime/size, `system.reg` mtime,
/// `drive_c/windows/explorer.exe` mtime/size — and compares it to a
/// fingerprint captured immediately after a *confirmed* successful
/// boot. A matching fingerprint is proof by construction that the
/// prefix is in the exact state wineboot leaves behind, so the entire
/// boot-check phase is skippable.
public struct PrefixFingerprint: Codable, Sendable, Equatable {
    public var updateTimestampMTime: Date
    public var updateTimestampSize: Int
    public var systemRegMTime: Date
    public var explorerMTime: Date
    public var explorerSize: Int

    init(
        updateTimestampMTime: Date,
        updateTimestampSize: Int,
        systemRegMTime: Date,
        explorerMTime: Date,
        explorerSize: Int
    ) {
        self.updateTimestampMTime = updateTimestampMTime
        self.updateTimestampSize = updateTimestampSize
        self.systemRegMTime = systemRegMTime
        self.explorerMTime = explorerMTime
        self.explorerSize = explorerSize
    }

    /// Fingerprint reduced to the boot-state witness tuple (registry
    /// mtime excluded — game runs mutate registry files freely).
    var bootWitness: PrefixFingerprint {
        PrefixFingerprint(
            updateTimestampMTime: updateTimestampMTime,
            updateTimestampSize: updateTimestampSize,
            systemRegMTime: .distantPast,
            explorerMTime: explorerMTime,
            explorerSize: explorerSize
        )
    }
}

public struct PrefixReadinessVerdict: Sendable, Equatable {
    /// True when the fingerprint match proves the prefix is
    /// boot-complete; the launch skips wineboot entirely.
    public let isReady: Bool

    /// Why the verdict was reached — for logs and telemetry.
    public let reason: String

    /// The fingerprint observed right now, to be persisted after the
    /// launch confirms the prefix worked.
    public let observed: PrefixFingerprint?
}

public struct PrefixBaseline: Sendable, Equatable {
    public let fingerprint: PrefixFingerprint
    public let engineBuildID: String

    public init(fingerprint: PrefixFingerprint, engineBuildID: String) {
        self.fingerprint = fingerprint
        self.engineBuildID = engineBuildID
    }
}

public enum PrefixReadinessOracle {
    static let explorerRelativePath = "drive_c/windows/explorer.exe"

    // MARK: - Observation

    public static func observe(bottleURL: URL) -> PrefixFingerprint? {
        let fileManager = FileManager.default
        let timestampURL = bottleURL.appending(path: ".update-timestamp")
        let systemRegURL = bottleURL.appending(path: "system.reg")
        let explorerURL = bottleURL.appending(path: explorerRelativePath)

        guard let timestampAttrs = attrs(of: timestampURL, fm: fileManager),
              let explorerAttrs = attrs(of: explorerURL, fm: fileManager) else {
            return nil
        }
        let systemRegAttrs = attrs(of: systemRegURL, fm: fileManager)

        return PrefixFingerprint(
            updateTimestampMTime: timestampAttrs.modification,
            updateTimestampSize: timestampAttrs.size,
            systemRegMTime: systemRegAttrs?.modification ?? .distantPast,
            explorerMTime: explorerAttrs.modification,
            explorerSize: explorerAttrs.size
        )
    }

    private static func attrs(of url: URL, fm fileManager: FileManager) -> (modification: Date, size: Int)? {
        guard let raw = try? fileManager.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let date = raw[.modificationDate] as? Date,
              let size = (raw[.size] as? NSNumber)?.intValue else {
            return nil
        }
        return (date, size)
    }

    // MARK: - Verdict

    /// Decide whether the launch can skip prefix boot-checking.
    ///
    /// - Parameters:
    ///   - bottleURL: prefix root.
    ///   - saved: fingerprint recorded the last time this prefix was
    ///     confirmed ready, against the wine build in use at that time.
    ///   - engineBuildID: opaque identity of the wine build about to run;
    ///     a different build invalidates the prediction (new wine ⇒ new
    ///     prefix upgrade work).
    public static func verdict(
        bottleURL: URL,
        saved: PrefixBaseline?,
        engineBuildID: String
    ) -> PrefixReadinessVerdict {
        guard let observed = observe(bottleURL: bottleURL) else {
            return PrefixReadinessVerdict(isReady: false, reason: "no-evidence", observed: nil)
        }
        guard let saved, saved.engineBuildID == engineBuildID else {
            return PrefixReadinessVerdict(
                isReady: false,
                reason: saved == nil ? "no-baseline" : "engine-changed",
                observed: observed
            )
        }
        // Registry files are mutated by every game run (wine flushes
        // its in-memory hive on shutdown), but their content does not
        // change boot state: wineboot rewrites .update-timestamp
        // whenever it changes prefix structure, so .update-timestamp is
        // the boot-state witness. systemRegMTime is recorded for
        // telemetry only and excluded from the equality that matters.
        let ready = observed.bootWitness == saved.fingerprint.bootWitness
        return PrefixReadinessVerdict(
            isReady: ready,
            reason: ready ? "fingerprint-match" : "prefix-evolved",
            observed: observed
        )
    }

    /// The subset of the fingerprint that identifies boot state.
    static func bootWitness(of fingerprint: PrefixFingerprint) -> PrefixFingerprint {
        fingerprint.bootWitness
    }

    // MARK: - Persistence

    nonisolated static var baselineURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier)
            .appending(path: "prefix-readiness.json")
    }

    struct Baseline: Codable, Sendable {
        var bottleKey: String
        var engineBuildID: String
        var fingerprint: PrefixFingerprint
    }

    private static let baselineLock = NSLock()

    public static func saveBaseline(
        bottleKey: String,
        engineBuildID: String,
        fingerprint: PrefixFingerprint
    ) {
        let baseline = Baseline(
            bottleKey: bottleKey,
            engineBuildID: engineBuildID,
            fingerprint: fingerprint
        )
        baselineLock.lock()
        defer { baselineLock.unlock() }
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        try? FileManager.default.createDirectory(
            at: baselineURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: baselineURL, options: .atomic)
    }

    public static func loadBaseline(bottleKey: String) -> PrefixBaseline? {
        baselineLock.lock()
        defer { baselineLock.unlock() }
        guard let data = try? Data(contentsOf: baselineURL),
              let baseline = try? JSONDecoder().decode(Baseline.self, from: data),
              baseline.bottleKey == bottleKey else {
            return nil
        }
        return PrefixBaseline(
            fingerprint: baseline.fingerprint,
            engineBuildID: baseline.engineBuildID
        )
    }

    public static func resetForTests() {
        baselineLock.lock()
        defer { baselineLock.unlock() }
        try? FileManager.default.removeItem(at: baselineURL)
    }
}
