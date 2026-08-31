//
//  ProgramRunFinalizer.swift
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

enum ProgramRunFinalizer {
    static func finalize(
        runID: UUID?,
        capture: ProgramRunCapture?,
        programURL: URL,
        bottle: Bottle,
        exitCode: Int32?
    ) async {
        if let runID {
            await MainActor.run {
                ProgramRunLogStore.shared.finishRun(runID: runID, exitCode: exitCode)
            }
            if let capture,
               let message = ProgramLaunchCoordinator.silentExitFailureMessage(capture: capture) {
                await MainActor.run {
                    ProgramLaunchCoordinator.shared.reportSilentExit(
                        programURL: programURL,
                        message: message
                    )
                }
            }
            if let capture {
                recordThroughputEvidence(
                    runID: runID,
                    capture: capture,
                    programURL: programURL,
                    exitCode: exitCode
                )
            }
        }
        BottleProcessRegistry.shared.unregisterFinished(for: bottle)
    }

    private static func recordThroughputEvidence(
        runID: UUID,
        capture: ProgramRunCapture,
        programURL: URL,
        exitCode: Int32?
    ) {
        let programKey = ProgramRunLogStore.programKey(for: programURL)
        let posture = GameBoostRegistry.profile(for: programKey)?.posture ?? .balanced
        let sessionSeconds = Date().timeIntervalSince(capture.record.startedAt)
        _ = FrameThroughputObserver.record(
            runID: runID,
            programKey: programKey,
            sessionSeconds: sessionSeconds,
            exitCode: exitCode,
            posture: posture
        )
    }
}
