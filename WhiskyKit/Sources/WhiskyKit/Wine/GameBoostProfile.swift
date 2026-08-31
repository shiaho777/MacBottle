//
//  GameBoostProfile.swift
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

/// A per-program, persisted performance posture.
///
/// Three tunings derived from the actual knob surface of the shipping
/// D3DMetal/MoltenVK stack (43 MVK_* + 20 D3DM_* environment switches,
/// enumerated from the installed dylibs) — not from folklore:
///
/// - `.skyline` chases peak frame rate. Every known latency cost is
///   removed: synchronous queue submits off, command-buffer prefill on,
///   Metal argument buffers on, descriptor preallocation on, concurrent
///   shader compilation maximized, swapchain filtering switched to
///   nearest (native-resolution crispness, no sampling latency).
/// - `.efficient` chases frames-per-watt: identical pipeline posture
///   plus forced low-power GPU selection where the Mac has two GPUs.
/// - `.balanced` is the default posture with debug/validation layers
///   pinned off (they are off already by Universal Defaults; this makes
///   the intent explicit and immune to inherited host environments).
public struct GameBoostProfile: Codable, Sendable, Equatable {
    public enum Posture: String, Codable, Sendable, CaseIterable {
        case balanced
        case skyline
        case efficient
    }

    public var posture: Posture

    /// When true the posture was chosen by the tuner from observed
    /// throughput, not by the user; a user choice always wins over it.
    public var autoTuned: Bool

    public init(posture: Posture, autoTuned: Bool = false) {
        self.posture = posture
        self.autoTuned = autoTuned
    }

    /// The environment overlay this posture contributes. Keys are merged
    /// after bottle settings but never override values the user set
    /// explicitly on the program or bottle.
    public func environmentOverlay() -> [String: String] {
        var env: [String: String] = [:]

        // Both postures share the "no avoidable overhead" pipeline.
        env["MVK_CONFIG_DEBUG"] = "0"
        env["MVK_CONFIG_TRACE_VULKAN_CALLS"] = "0"
        env["MVK_CONFIG_PERFORMANCE_TRACKING"] = "0"
        env["MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE"] = "none"
        env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] = "0"
        env["MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER"] = "0"
        env["MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS"] = "1"
        env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = "1"
        env["MVK_CONFIG_PREALLOCATE_DESCRIPTORS"] = "1"
        env["MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE"] = "32"
        env["MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION"] = "1"
        env["MVK_CONFIG_USE_COMMAND_POOLING"] = "1"
        env["MVK_CONFIG_USE_MTLHEAP"] = "1"
        env["MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS"] = "1"
        env["MVK_CONFIG_METAL_COMPILE_TIMEOUT"] = "0"
        env["MVK_CONFIG_SWAPCHAIN_MIN_MAG_FILTER_USE_NEAREST"] = "1"
        env["D3DM_MULTITHREADED_INTERFACE_ENABLE"] = "1"

        switch posture {
        case .skyline:
            env["MVK_CONFIG_FORCE_LOW_POWER_GPU"] = "0"
        case .efficient:
            // Frames per watt: prefer the integrated GPU when present.
            env["MVK_CONFIG_FORCE_LOW_POWER_GPU"] = "1"
        case .balanced:
            break
        }
        return env
    }
}

/// Persists one profile per program (keyed by stable program key) so a
/// game remembers its posture across launches and across bottle moves.
public enum GameBoostRegistry {
    struct Store: Codable, Sendable {
        var profiles: [String: GameBoostProfile] = [:]
    }

    nonisolated static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier)
            .appending(path: "game-boost.json")
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Store?

    public static func profile(for programKey: String) -> GameBoostProfile? {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached.profiles[programKey]
        }
        let store = loadStore()
        cached = store
        return store.profiles[programKey]
    }

    public static func setProfile(_ profile: GameBoostProfile?, for programKey: String) {
        lock.lock()
        defer { lock.unlock() }
        var store = cached ?? loadStore()
        if let profile {
            store.profiles[programKey] = profile
        } else {
            store.profiles.removeValue(forKey: programKey)
        }
        cached = store
        if let data = try? JSONEncoder().encode(store) {
            try? FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func loadStore() -> Store {
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store()
        }
        return store
    }

    public static func resetForTests() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        try? FileManager.default.removeItem(at: storeURL)
    }
}
