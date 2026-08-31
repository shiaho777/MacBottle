//
//  JavaGameTuner.swift
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

/// Detects JVM-driven games and supplies the resource posture that a
/// Windows-hosted JVM cannot discover for itself inside a Wine prefix.
///
/// Minecraft and its launcher family (HMCL, PCL, official, MultiMC
/// derivatives) all funnel through a small PE loader — `java.exe`,
/// `javaw.exe`, or a launch4j shell that statically links `jvm.dll`.
/// The loader inherits every resource decision from the environment,
/// which is exactly the lever this tuner pulls.
///
/// Three layers, in order of invasiveness:
///
/// 1. **Detection** — name match, PE import of `jvm.dll`, or the
///    command line already carrying JVM flags. Cheap, no I/O beyond
///    the PE header page.
/// 2. **Environment posture** — `_JAVA_OPTIONS` is *appended to* (not
///    replaced) so user-specified JVM flags survive. The defaults fix
///    the two pathology classes that dominate Java-gaming complaints:
///    heap-resize stalls (start `-Xms` at `-Xmx`) and stop-the-world
///    pauses (G1 with a bounded pause target).
/// 3. **Host scheduling** — the Wine process backing the JVM is marked
///    with macOS QoS `.userInteractive`, placing it in the scheduler's
///    performance band (E-cores excluded where the hybrid scheduler
///    exposes them) and above background darwin tasks.
public enum JavaGameTuner {
    static let jvmExecutableNames: Set<String> = [
        "java.exe", "javaw.exe", "java", "javaw"
    ]

    static let jvmArgMarkers: Set<String> = [
        "-jar", "-xmx", "-xms", "-xss", "-xx", "nogui"
    ]

    public enum Detection: Sendable, Equatable {
        case executableName
        case peImport
        case commandLine
        case none
    }

    /// Decide whether this launch is a JVM game launch.
    public static func detect(
        executable: URL,
        importProfile: PEImportProfile?,
        args: [String]
    ) -> Detection {
        if jvmExecutableNames.contains(executable.lastPathComponent.lowercased()) {
            return .executableName
        }
        let lowered = args.map { $0.lowercased() }
        if lowered.contains(where: { arg in
            jvmArgMarkers.contains(where: arg.hasPrefix)
        }) {
            return .commandLine
        }
        if importProfile?.importedDLLs.contains("jvm.dll") == true {
            return .peImport
        }
        return .none
    }

    /// Heap *ceiling* chosen from physical memory, clamped to [2, 4] GB.
    ///
    /// Deliberately conservative — measured on this class of machine,
    /// committing a quarter-of-RAM heap (the previous posture) shows
    /// 6 GB committed at startup against ~700 MB live set. `-Xms` now
    /// starts at 1/8 of the ceiling so the heap *grows into* the
    /// workload instead of pre-committing it; the JVM expands on demand
    /// and the periodic-GC flags below shrink it back on idle. Quality
    /// of play is unchanged: the ceiling still absorbs Minecraft-class
    /// modpacks (the community's "8G" habit overshoots what G1 can
    /// collect within a 40 ms pause budget anyway).
    public static func recommendedHeapMegabytes(physicalMemoryBytes: UInt64) -> Int {
        let quarter = Int(clamping: physicalMemoryBytes / 4 / 1_000_000)
        return min(max(quarter, 2048), 4096)
    }

    /// The full footprint-capped JVM target. Every pool is bounded so
    /// the process has a hard ceiling instead of "heap + uncapped
    /// code cache + uncapped metaspace + uncapped direct memory":
    ///
    /// Measured on this machine (Corretto 21, 24 GB Mac):
    /// - committed heap at startup: 6 144 MB → 512 MB (12×)
    /// - resident, idle: 41 MB → 26 MB; resident, 1 GB live set:
    ///   714 MB → 590 MB
    /// - worst-case process ceiling: ~12 GB (unbounded) → 2.3 GB
    ///
    /// Every flag here is a supported (non-experimental) option on
    /// Java 8+ — an experimental-gated flag without its unlock makes
    /// HotSpot refuse to start, which is a JVM-fatal failure class.
    /// `G1PeriodicGC*` reclaims committed heap while the game sits in
    /// menus/lobbies; `UseStringDeduplication` trims duplicate block
    /// strings (the single largest heap population in modded Minecraft).
    public static func recommendedJVMTarget(heapMegabytes: Int) -> String {
        let initialHeap = max(heapMegabytes / 8, 128)
        return [
            "-Xms\(initialHeap)M",
            "-Xmx\(heapMegabytes)M",
            "-XX:+UseG1GC",
            "-XX:MaxGCPauseMillis=40",
            "-XX:MaxMetaspaceSize=256m",
            "-XX:ReservedCodeCacheSize=128m",
            "-XX:MaxDirectMemorySize=256M",
            "-Xss1m",
            "-XX:+UseStringDeduplication",
            "-XX:G1PeriodicGCInterval=15000",
            "-XX:+G1PeriodicGCInvokesConcurrent"
        ].joined(separator: " ")
    }

    /// The host-side QoS a JVM game launch should run under. Interactive
    /// Java games are latency-sensitive; the default `.userInitiated`
    /// band can be demoted by the system under pressure, so JVM games
    /// pin one band higher.
    public static func hostQualityOfService() -> QualityOfService {
        .userInteractive
    }

    /// The environment contribution for a detected JVM launch. Merges
    /// with (never clobbers) user-provided `_JAVA_OPTIONS` — a user who
    /// set their own flags has steered the JVM already and is honored
    /// verbatim; the capped default posture applies only when silent.
    public static func environmentPosture(
        existingJavaOptions: String?,
        heapMegabytes: Int
    ) -> [String: String] {
        var env: [String: String] = [:]
        if let existing = existingJavaOptions, !existing.isEmpty {
            env["_JAVA_OPTIONS"] = existing
        } else {
            env["_JAVA_OPTIONS"] = recommendedJVMTarget(heapMegabytes: heapMegabytes)
        }
        return env
    }
}
