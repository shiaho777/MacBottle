//
//  LaunchLatencyTelemetry.swift
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

/// Ground-truth "what did a launch actually cost" ledger. Every
/// `Wine.runProgram` appends one event with the wall-clock spans of the
/// serial phases that sit between the user's click and the wine spawn.
/// `PrefixReadinessOracle` replays this ledger to learn, per bottle,
/// whether its predictions were honored and what the residual latency
/// is made of.
public struct LaunchLatencyEvent: Codable, Sendable, Equatable {
    public var bottleKey: String
    public var startedAt: Date

    /// Seconds spent proving the prefix is boot-complete and mutating
    /// per-launch registry policy (RetinaMode, LogPixels). Near zero when
    /// a predicted launch short-circuits both.
    public var readinessSeconds: TimeInterval

    /// Seconds from readiness completion to wine process spawn
    /// (DXVK install, env merge, coordinator bookkeeping).
    public var dispatchSeconds: TimeInterval

    public init(
        bottleKey: String,
        startedAt: Date,
        readinessSeconds: TimeInterval,
        dispatchSeconds: TimeInterval
    ) {
        self.bottleKey = bottleKey
        self.startedAt = startedAt
        self.readinessSeconds = readinessSeconds
        self.dispatchSeconds = dispatchSeconds
    }
}

public enum LaunchLatencyTelemetry {
    static let maxEvents = 200

    nonisolated(unsafe) private static var events: [LaunchLatencyEvent] = []
    private static let lock = NSLock()

    nonisolated static var ledgerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier)
            .appending(path: "launch-latency.json")
    }

    public static func record(_ event: LaunchLatencyEvent) {
        lock.lock()
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        let snapshot = events
        let url = ledgerURL
        lock.unlock()

        let data = try? JSONEncoder().encode(snapshot)
        if let data {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func recentEvents() -> [LaunchLatencyEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public static func loadPersisted() {
        guard let data = try? Data(contentsOf: ledgerURL),
              let decoded = try? JSONDecoder().decode([LaunchLatencyEvent].self, from: data) else {
            return
        }
        lock.lock()
        events = Array(decoded.suffix(maxEvents))
        lock.unlock()
    }

    public static func resetForTests() {
        lock.lock()
        events.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: ledgerURL)
    }

    static func logSummary() {
        let recent = recentEvents().suffix(10)
        guard !recent.isEmpty else { return }
        let readiness = recent.map(\.readinessSeconds).reduce(0, +) / Double(recent.count)
        let dispatch = recent.map(\.dispatchSeconds).reduce(0, +) / Double(recent.count)
        let readinessText = String(format: "%.2f", readiness)
        let dispatchText = String(format: "%.2f", dispatch)
        Logger.wineKit.info(
            // swiftlint:disable:next line_length
            "Launch latency (last \(recent.count) runs): readiness \(readinessText, privacy: .public)s, dispatch \(dispatchText, privacy: .public)s"
        )
    }
}
