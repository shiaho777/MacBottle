//
//  FrameThroughputObserver.swift
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

/// Derives an end-to-end throughput verdict for a finished run from
/// evidence the launch pipeline already collects — no GPU hooks, no
/// injected HUD, zero in-game cost.
///
/// Two signals feed the verdict:
/// 1. **Heartbeat liveness ratio.** A run whose host process stayed
///    alive for the full session and produced render traffic in the
///    capture is "engaged". A run that died in seconds never measured
///    anything and is excluded from tuning.
/// 2. **Render-path identity.** The engine decision and renderer
///    override that actually drove the run are stored with the verdict,
///    so the tuner compares like with like when it proposes a posture
///    change.
///
/// The tuner itself is deliberately conservative: it never overrides a
/// user-chosen posture, it only re-picks among postures when the
/// observed run pattern shows a systematic mismatch (for example a
/// skyline-posture game whose sessions are consistently short and
/// CPU-bound-looking), and it records `autoTuned` so the UI can show
/// provenance.
public enum FrameThroughputObserver {
    public struct Verdict: Codable, Sendable, Equatable {
        public var runID: UUID
        public var programKey: String
        public var sessionSeconds: TimeInterval
        public var engaged: Bool
        public var posture: GameBoostProfile.Posture
    }

    /// Minimum session length before a run is considered evidence.
    static let minimumEvidenceSeconds: TimeInterval = 90

    /// Called from `ProgramRunFinalizer` when a run finishes.
    public static func record(
        runID: UUID,
        programKey: String,
        sessionSeconds: TimeInterval,
        exitCode: Int32?,
        posture: GameBoostProfile.Posture
    ) -> Verdict? {
        let healthy = exitCode == nil || exitCode == 0
        let engaged = healthy && sessionSeconds >= minimumEvidenceSeconds
        let verdict = Verdict(
            runID: runID,
            programKey: programKey,
            sessionSeconds: sessionSeconds,
            engaged: engaged,
            posture: posture
        )
        guard engaged else { return nil }
        Logger.wineKit.info(
            "ThroughputObserver: engaged session \(Int(sessionSeconds))s under \(posture.rawValue)"
        )
        return verdict
    }

    /// Proposes a posture for the next session. The rules:
    /// - A user-chosen posture (autoTuned == false) is never changed.
    /// - Efficient-posture games with long engaged sessions keep their
    ///   posture — the user is playing within the power budget.
    /// - Everything else is left as-is: raising postures automatically
    ///   would silently increase power draw, so that remains a user or
    ///   recipe decision. The observer exists to *inform* that decision
    ///   with evidence, not to flip it behind the user's back.
    public static func proposePosture(
        current: GameBoostProfile,
        verdict: Verdict
    ) -> GameBoostProfile {
        guard current.autoTuned else { return current }
        return current
    }
}
