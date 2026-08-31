//
//  DoubleLaunchExecutor.swift
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

/// The DoubleLaunch discipline: the first time a program runs in a
/// bottle, the launch deliberately re-executes itself once (transparent
/// to the program — `start.exe /wait` semantics are preserved), using
/// the first pass purely to drive the prefix to its confirmed-ready
/// state and capture the readiness fingerprint. Every subsequent
/// launch of that program consults `PrefixReadinessOracle`; when the
/// fingerprint matches, all boot-check and display-policy work is
/// skipped and the wine binary is exec'd directly — the "ZeroPath".
///
/// Why re-execution instead of a warmup pass on a dummy binary: a real
/// `wineboot -u` costs 10–15 s and produces exactly the state the first
/// real launch needs anyway (C-drive scaffolding, registry promotion,
/// wininit). Folding it into the first launch means the user waits
/// *once, on first run only*, and the second-and-later launches — the
/// ones users actually feel — pay zero readiness cost.
public struct DoubleLaunchPlan: Sendable, Equatable {
    /// Fingerprint proved the prefix ready (ZeroPath taken).
    public let readinessSkipped: Bool
    /// First confirmed run for this (bottle, engine): the caller
    /// re-execs the program once to arm the baseline.
    public let doubleLaunch: Bool
    public let observed: PrefixFingerprint?
}

public enum DoubleLaunchExecutor {
    public struct PassRecord: Codable, Sendable, Equatable {
        public var doubleLaunch: Bool
        public var readinessSkipped: Bool

        public init(doubleLaunch: Bool, readinessSkipped: Bool) {
            self.doubleLaunch = doubleLaunch
            self.readinessSkipped = readinessSkipped
        }
    }

    static let passDefaultsKey = "macbottle.doubleLaunch.pass"

    /// Returns the pass record encoded in `environment`, if any.
    public static func passRecord(from environment: [String: String]) -> PassRecord? {
        guard let raw = environment[Self.passDefaultsKey] else { return nil }
        guard let data = raw.data(using: .utf8),
              let record = try? JSONDecoder().decode(PassRecord.self, from: data) else {
            return nil
        }
        return record
    }

    static func injecting(record: PassRecord, into environment: [String: String]) -> [String: String] {
        guard let data = try? JSONEncoder().encode(record),
              let raw = String(data: data, encoding: .utf8) else {
            return environment
        }
        var env = environment
        env[Self.passDefaultsKey] = raw
        return env
    }

    /// Decide the shape of this launch.
    public static func plan(
        bottle: Bottle,
        fingerprintSaved: PrefixBaseline?,
        engineBuildID: String
    ) -> DoubleLaunchPlan {
        let verdict = PrefixReadinessOracle.verdict(
            bottleURL: bottle.url,
            saved: fingerprintSaved,
            engineBuildID: engineBuildID
        )
        if verdict.isReady {
            return DoubleLaunchPlan(
                readinessSkipped: true,
                doubleLaunch: false,
                observed: verdict.observed
            )
        }
        // Unproven prefix: if no baseline exists at all this is the
        // first run, so take the confirming double launch. If a
        // baseline exists but drifted (engine upgrade, wineboot ran
        // externally), this launch runs single-pass with readiness
        // work; the next successful launch re-arms the baseline.
        let hasBaseline = fingerprintSaved != nil
        return DoubleLaunchPlan(
            readinessSkipped: false,
            doubleLaunch: !hasBaseline,
            observed: verdict.observed
        )
    }

    /// Capture the readiness fingerprint after a launch that provably
    /// reached the running state, arming the ZeroPath for future runs.
    public static func armBaseline(bottle: Bottle, engineBuildID: String) {
        guard let fingerprint = PrefixReadinessOracle.observe(bottleURL: bottle.url) else {
            return
        }
        PrefixReadinessOracle.saveBaseline(
            bottleKey: ProgramRunLogStore.bottleKey(for: bottle),
            engineBuildID: engineBuildID,
            fingerprint: fingerprint
        )
        let name = bottle.settings.name
        Logger.wineKit.info("ZeroPath: readiness baseline armed for \(name)")
    }

    static func markExecApplied(record: PassRecord, environment: inout [String: String]) {
        var updated = record
        updated.doubleLaunch = false
        if let data = try? JSONEncoder().encode(updated),
           let raw = String(data: data, encoding: .utf8) {
            environment[Self.passDefaultsKey] = raw
        }
    }
}
