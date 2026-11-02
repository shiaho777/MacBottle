//
//  RendererEnvironment.swift
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

/// Environment policy for the renderer that is *not* DXVK.
///
/// macOS has no Apple-supplied Vulkan driver. A Vulkan title reaches Metal
/// through `winevulkan.dll` → the host Vulkan loader → MoltenVK. DXVK is
/// only for D3D9/10/11; putting it on a Vulkan title's path adds a
/// translation hop that buys nothing.
///
/// Everything here is conservative and opt-out: the variables are read by
/// MoltenVK at device creation, and removing them restores the engine's
/// defaults.
public enum RendererEnvironment {
    /// MoltenVK settings that are safe across the shipped engine range.
    /// They reduce per-frame bookkeeping and swapchain churn without
    /// changing rendering semantics.
    public static func moltenVKDefaults() -> [String: String] {
        [
            // Only surface errors; MoltenVK's info logging is not free.
            "MVK_CONFIG_LOG_LEVEL": "1",
            // Allocate swapchain images up front instead of stalling on
            // the first present of each frame.
            "MVK_CONFIG_PREALLOCATE_SWAPCHAIN_IMAGES": "1",
            // Do not block the CPU on every queue submit; Metal can
            // pipeline the work.
            "MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS": "0",
            // A lost device (GPU hang, display change) should recreate
            // rather than tear the process down.
            "MVK_CONFIG_RESUME_LOST_DEVICE": "1"
        ]
    }

    /// Locate MoltenVK's ICD manifest inside an engine install.
    public static func moltenVKICDManifest(in engine: any WineEngine) -> URL? {
        let candidates = [
            engine.libraryRoot.appending(path: "Wine/lib/external/MoltenVK_icd.json"),
            engine.libraryRoot.appending(path: "Wine/lib/MoltenVK_icd.json"),
            engine.libraryRoot.appending(path: "MoltenVK/MoltenVK_icd.json"),
            engine.libraryRoot.appending(path: "MoltenVK_icd.json")
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
    }

    /// Apply the Vulkan-through-MoltenVK posture. Idempotent: callers may
    /// invoke it on every launch.
    public static func applyMoltenVK(
        to environment: inout [String: String],
        engine: (any WineEngine)? = nil
    ) {
        for (key, value) in moltenVKDefaults() {
            environment[key] = value
        }
        if let engine, let icd = moltenVKICDManifest(in: engine) {
            environment["VK_ICD_FILENAMES"] = icd.path(percentEncoded: false)
        }
        // Explicitly keep Wine's own Vulkan loader. A stale DXVK-style
        // override such as `vulkan-1=n,b` would hand the game a DLL that
        // cannot speak to MoltenVK.
        environment["WINEDLLOVERRIDES"] = mergingOverride(
            "vulkan-1=b",
            into: environment["WINEDLLOVERRIDES"]
        )
    }

    /// Make sure DXVK/WineD3D overrides are not left in a contradictory
    /// state when a recipe asks for pure WineD3D.
    public static func applyWineD3D(to environment: inout [String: String]) {
        environment.removeValue(forKey: "DXVK_HUD")
        environment.removeValue(forKey: "DXVK_ASYNC")
        environment.removeValue(forKey: "DXVK_CONFIG_FILE")
        let keys = ["dxgi", "d3d9", "d3d10core", "d3d11"]
        for key in keys {
            environment["WINEDLLOVERRIDES"] = mergingOverride(
                "\(key)=b",
                into: environment["WINEDLLOVERRIDES"]
            )
        }
    }

    /// D3D11 through DXMT: one hop to Metal, no DXVK/Vulkan stage.
    public static func applyDXMT(to environment: inout [String: String]) {
        environment.removeValue(forKey: "DXVK_HUD")
        environment.removeValue(forKey: "DXVK_ASYNC")
        environment.removeValue(forKey: "DXVK_CONFIG_FILE")
        for key in ["dxgi", "d3d11"] {
            environment["WINEDLLOVERRIDES"] = mergingOverride(
                "\(key)=n,b",
                into: environment["WINEDLLOVERRIDES"]
            )
        }
    }

    /// D3D12 through vkd3d-proton → Vulkan → MoltenVK.
    public static func applyVKD3D(to environment: inout [String: String]) {
        environment.removeValue(forKey: "DXVK_HUD")
        environment.removeValue(forKey: "DXVK_ASYNC")
        environment.removeValue(forKey: "DXVK_CONFIG_FILE")
        for key in ["dxgi", "d3d12"] {
            environment["WINEDLLOVERRIDES"] = mergingOverride(
                "\(key)=n,b",
                into: environment["WINEDLLOVERRIDES"]
            )
        }
    }

    static func mergingOverride(_ entry: String, into existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return entry }
        var parts = existing
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let key = entry.split(separator: "=").first.map(String.init) ?? entry
        parts.removeAll { $0.split(separator: "=").first.map(String.init) == key }
        parts.append(entry)
        return parts.joined(separator: ";")
    }
}
