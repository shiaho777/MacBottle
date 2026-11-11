//
//  WinePrewarm.swift
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
import os.log

extension Wine {
    public static func prewarmBottle(_ bottle: Bottle, engine: (any WineEngine)? = nil) async throws {
        let engine = engine ?? WineEngineRegistry.shared.current
        let engineID = buildID(for: engine)
        let gate = await MainActor.run { () -> String in
            if ProgramLaunchCoordinator.shared.isWarm(bottle: bottle, engineID: engineID) {
                return "warm"
            }
            if ProgramLaunchCoordinator.shared.isWarming(bottle: bottle, engineID: engineID) {
                return "warming"
            }
            ProgramLaunchCoordinator.shared.beginWarmup(bottle: bottle, engineID: engineID)
            return "start"
        }

        if gate == "warm" {
            return
        }
        if gate == "warming" {
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(40))
                let done = await MainActor.run {
                    ProgramLaunchCoordinator.shared.isWarm(bottle: bottle, engineID: engineID)
                        || !ProgramLaunchCoordinator.shared.isWarming(bottle: bottle, engineID: engineID)
                }
                if done {
                    return
                }
            }
            return
        }

        // ZeroPath: the readiness oracle can prove the prefix is
        // boot-complete from on-disk evidence alone. When it does, the
        // "prewarm" is genuinely instant — nothing to spawn at all.
        let bottleKey = ProgramRunLogStore.bottleKey(for: bottle)
        let baseline = PrefixReadinessOracle.loadBaseline(bottleKey: bottleKey)
        let verdict = PrefixReadinessOracle.verdict(
            bottleURL: bottle.url,
            saved: baseline,
            engineBuildID: engineID
        )
        if verdict.isReady {
            Logger.wineKit.info("ZeroPath: prewarm skipped (readiness proven)")
            await MainActor.run {
                ProgramLaunchCoordinator.shared.markWarm(bottle: bottle, engineID: engineID)
            }
            return
        }

        do {
            // wineserver is the IPC hub every wine call round-trips —
            // per-frame present() and every input event included. A
            // .utility band here demotes the entire bottle's response
            // chain; the scheduler keeps it in the interactive band
            // with the game instead.
            let process = try ProcessRunner.launch(
                executable: engine.wineserverBinary,
                arguments: ["-p"],
                environment: constructWineServerEnvironment(for: bottle, engine: engine),
                qualityOfService: .userInteractive
            )
            BottleProcessRegistry.shared.register(process, bottle: bottle)

            try await Task.sleep(for: .milliseconds(150))
            let success = process.isRunning || process.terminationStatus == 0
            await MainActor.run {
                ProgramLaunchCoordinator.shared.finishWarmup(
                    bottle: bottle,
                    engineID: engineID,
                    success: success
                )
            }
        } catch {
            await MainActor.run {
                ProgramLaunchCoordinator.shared.finishWarmup(
                    bottle: bottle,
                    engineID: engineID,
                    success: false
                )
            }
            throw error
        }
    }

    public static func ensureBottleReady(
        _ bottle: Bottle,
        engine: (any WineEngine)? = nil
    ) async {
        do {
            try await prewarmBottle(bottle, engine: engine)
        } catch {
            Logger.wineKit.warning(
                "Bottle prewarm skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Stable identity for "which Wine build is this". Used to invalidate
    /// warm state and readiness baselines when the build changes.
    public static func buildID(for engine: any WineEngine) -> String {
        "\(engine.identifier)-\(engine.installedVersion()?.description ?? "unknown")"
    }
}
