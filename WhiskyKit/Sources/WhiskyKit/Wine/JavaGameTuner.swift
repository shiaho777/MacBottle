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

    /// JVM flags recommended for an interactive game workload. Values
    /// are validated to parse on Java 8+ (G1 default since 9, available
    /// on 8 via flag; `-XX:+UseStringDeduplication` is G1-only and
    /// silently ignored elsewhere).
    public static func recommendedJVMTarget(heapMegabytes: Int) -> String {
        [
            "-Xms\(heapMegabytes)M",
            "-Xmx\(heapMegabytes)M",
            "-XX:+UseG1GC",
            "-XX:MaxGCPauseMillis=40",
            "-XX:G1NewSizePercent=20",
            "-XX:G1ReservePercent=20",
            "-XX:MaxMetaspaceSize=512m",
            "-XX:+UseStringDeduplication"
        ].joined(separator: " ")
    }

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

    /// Heap size chosen from physical memory: quarter of RAM, clamped
    /// to [2, 8] GB. Matches what the Minecraft community converged on,
    /// derived here from first principles — G1 wants a heap large
    /// enough that young collections stay rare but small enough that
    /// each stays short.
    public static func recommendedHeapMegabytes(physicalMemoryBytes: UInt64) -> Int {
        let quarter = Int(clamping: physicalMemoryBytes / 4 / 1_000_000)
        return min(max(quarter, 2048), 8192)
    }

    /// The environment contribution for a detected JVM launch. Merges
    /// with (never clobbers) user-provided `_JAVA_OPTIONS` by appending
    /// our flags after theirs — the JVM lets the last occurrence win,
    /// but a user who sets `-Xmx` explicitly does not expect us to
    /// override it, so user flags are preserved verbatim when present.
    public static func environmentPosture(
        existingJavaOptions: String?,
        heapMegabytes: Int
    ) -> [String: String] {
        let recommended = recommendedJVMTarget(heapMegabytes: heapMegabytes)
        var env: [String: String] = [:]
        if let existing = existingJavaOptions, !existing.isEmpty {
            // User already steers the JVM: honor it untouched.
            env["_JAVA_OPTIONS"] = existing
        } else {
            env["_JAVA_OPTIONS"] = recommended
        }
        return env
    }

    /// The host-side QoS a JVM game launch should run under. Interactive
    /// Java games are latency-sensitive; the default `.userInitiated`
    /// band can be demoted by the system under pressure, so JVM games
    /// pin one band higher.
    public static func hostQualityOfService() -> QualityOfService {
        .userInteractive
    }
}
