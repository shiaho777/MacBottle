//
//  RuntimeLaunchOptimizer.swift
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

public enum RuntimeProfile: String, Sendable, Hashable {
    case classic32
    case modern64
    case installer
    case generic
}

public enum RuntimeLaunchOptimizer {
    private static let profileCacheLock = NSLock()
    nonisolated(unsafe) private static var profileCache: [String: (mod: Date, size: UInt64, profile: RuntimeProfile)] = [:]

    public static func profile(for pe: PEFile?) -> RuntimeProfile {
        guard let pe else { return .generic }
        switch pe.architecture {
        case .x32:
            return .classic32
        case .x64:
            return .modern64
        case .unknown:
            return .generic
        }
    }

    public static func profile(forExecutableAt url: URL?) -> RuntimeProfile {
        guard let url else { return .generic }
        let name = url.lastPathComponent.lowercased()
        if name.contains("setup")
            || name.contains("install")
            || name.contains("uninst")
            || name.hasSuffix(".msi") {
            return .installer
        }

        let path = url.path(percentEncoded: false)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mod = attrs?[.modificationDate] as? Date ?? .distantPast
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0

        profileCacheLock.lock()
        if let cached = profileCache[path], cached.mod == mod, cached.size == size {
            let value = cached.profile
            profileCacheLock.unlock()
            return value
        }
        profileCacheLock.unlock()

        let resolved: RuntimeProfile
        do {
            let pe = try PEFile(url: url)
            resolved = profile(for: pe)
        } catch {
            resolved = .generic
        }

        profileCacheLock.lock()
        profileCache[path] = (mod, size, resolved)
        profileCacheLock.unlock()
        return resolved
    }

    public static func environment(
        profile: RuntimeProfile,
        bottleDXVKEnabled: Bool,
        base: [String: String],
        d3dMetalStatus: D3DMetalStatus? = nil
    ) -> [String: String] {
        var env = base
        applyUniversalModernDefaults(&env, bottleDXVKEnabled: bottleDXVKEnabled)

        switch profile {
        case .classic32:
            applyClassic32(&env)
        case .modern64:
            applyModern64(&env, bottleDXVKEnabled: bottleDXVKEnabled)
        case .installer:
            applyInstaller(&env)
        case .generic:
            break
        }

        let status = d3dMetalStatus ?? D3DMetalCapability.probe()
        let d3dm = D3DMetalCapability.environmentContributions(
            status: status,
            profile: profile,
            bottleDXVKEnabled: bottleDXVKEnabled
        )
        for (key, value) in d3dm {
            if env[key] == nil {
                env[key] = value
            }
        }

        return env
    }

    public static func startArguments(
        profile: RuntimeProfile,
        executable: URL,
        extraArgs: [String]
    ) -> [String] {
        var args = ["start"]
        switch profile {
        case .classic32, .modern64, .generic:
            args.append("/high")
        case .installer:
            break
        }
        args.append(contentsOf: ["/unix", executable.path(percentEncoded: false)])
        args.append(contentsOf: extraArgs)
        return args
    }

    public static func processQualityOfService(for profile: RuntimeProfile) -> QualityOfService {
        switch profile {
        case .classic32, .modern64, .generic:
            return .userInteractive
        case .installer:
            return .userInitiated
        }
    }

    public static func shouldQuietProcessOutput(for profile: RuntimeProfile) -> Bool {
        switch profile {
        case .classic32, .modern64, .generic:
            return true
        case .installer:
            return false
        }
    }

    private static func applyUniversalModernDefaults(
        _ env: inout [String: String],
        bottleDXVKEnabled: Bool
    ) {
        if env["WINEDEBUG"] == nil || env["WINEDEBUG"] == "fixme-all" {
            env["WINEDEBUG"] = "-all"
        }
        if env["GST_DEBUG"] == nil || env["GST_DEBUG"] == "1" {
            env["GST_DEBUG"] = "0"
        }

        mergeDLLOverrides(
            &env,
            additions: "winemenubuilder.exe=d;winedbg.exe=d;winemine.exe=d"
        )

        env["MVK_CONFIG_DEBUG"] = env["MVK_CONFIG_DEBUG"] ?? "0"
        env["MVK_CONFIG_TRACE_VULKAN_CALLS"] = env["MVK_CONFIG_TRACE_VULKAN_CALLS"] ?? "0"
        env["MVK_CONFIG_FAST_MATH_ENABLED"] = env["MVK_CONFIG_FAST_MATH_ENABLED"] ?? "1"
        env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] =
            env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] ?? "1"
        env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] =
            env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] ?? "0"
        env["MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER"] =
            env["MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER"] ?? "0"
        env["MVK_CONFIG_FORCE_LOW_POWER_GPU"] = env["MVK_CONFIG_FORCE_LOW_POWER_GPU"] ?? "0"
        env["MTL_SHADER_VALIDATION"] = env["MTL_SHADER_VALIDATION"] ?? "0"
        env["MTL_DEBUG_LAYER"] = env["MTL_DEBUG_LAYER"] ?? "0"
        env["MTL_CAPTURE_ENABLED"] = env["MTL_CAPTURE_ENABLED"] ?? "0"

        if bottleDXVKEnabled {
            env["DXVK_LOG_LEVEL"] = env["DXVK_LOG_LEVEL"] ?? "none"
            env["DXVK_LOG_PATH"] = env["DXVK_LOG_PATH"] ?? "none"
            env["DXVK_STATE_CACHE"] = env["DXVK_STATE_CACHE"] ?? "1"
            env["DXVK_HUD"] = env["DXVK_HUD"] ?? ""
        }
    }

    private static func applyClassic32(_ env: inout [String: String]) {
        env.removeValue(forKey: "ROSETTA_ADVERTISE_AVX")
        env["WINE_DISABLE_KERNEL_WRITEWATCH"] = env["WINE_DISABLE_KERNEL_WRITEWATCH"] ?? "1"
        env["DXVK_ASYNC"] = "0"
        env["DXVK_LOG_LEVEL"] = "none"
        mergeDLLOverrides(&env, additions: "d3d12=d")
    }

    private static func applyModern64(
        _ env: inout [String: String],
        bottleDXVKEnabled: Bool
    ) {
        if bottleDXVKEnabled {
            env["DXVK_FRAME_RATE"] = env["DXVK_FRAME_RATE"] ?? "0"
        }
    }

    private static func applyInstaller(_ env: inout [String: String]) {
        env["WINEDEBUG"] = env["WINEDEBUG"] ?? "-all"
        env["DXVK_ASYNC"] = "0"
        env.removeValue(forKey: "ROSETTA_ADVERTISE_AVX")
    }

    private static func mergeDLLOverrides(
        _ env: inout [String: String],
        additions: String
    ) {
        let existing = env["WINEDLLOVERRIDES"] ?? ""
        var parts = existing
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let additionParts = additions
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for part in additionParts {
            let key = part.split(separator: "=").first.map(String.init) ?? part
            if !parts.contains(where: {
                $0.split(separator: "=").first.map(String.init) == key
            }) {
                parts.append(part)
            }
        }

        if !parts.isEmpty {
            env["WINEDLLOVERRIDES"] = parts.joined(separator: ";")
        }
    }
}
