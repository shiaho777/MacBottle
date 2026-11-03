//
//  DownloadBridge.swift
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

/// Dual-plane architecture:
/// - Data plane: macOS native HTTP / steamcmd
/// - Control plane: Wine only launches Steam / game
public enum DownloadBridge {
    public static func seedSteamClient(
        bottleURL: URL,
        onProgress: (@Sendable (DownloadProgress, String) -> Void)? = nil
    ) async throws -> SteamClientSeedResult {
        try await SteamClientSeeder.shared.seed(intoBottle: bottleURL, onProgress: onProgress)
    }

    public static func downloadGameDepot(
        appID: Int,
        credentials: SteamCredentials,
        intoBottle bottleURL: URL,
        onProgress: (@Sendable (SteamCMDProgress) -> Void)? = nil
    ) async throws {
        let engine = SteamCMDEngine.shared
        let store = DepotStore()

        if !store.isDepotPresent(appID: appID) {
            try await engine.updateApp(
                appID: appID,
                credentials: credentials,
                validate: true,
                onProgress: onProgress
            )
        } else {
            onProgress?(
                SteamCMDProgress(
                    fraction: 0.9,
                    detail: "Depot already in native cache — materializing…",
                    bytesPerSecond: 0,
                    state: .validating
                )
            )
        }

        onProgress?(
            SteamCMDProgress(
                fraction: 0.95,
                detail: "Cloning depot into bottle (APFS clone when possible)…",
                bytesPerSecond: 0,
                state: .validating
            )
        )
        try store.materializeDepot(appID: appID, intoBottle: bottleURL)
        onProgress?(
            SteamCMDProgress(
                fraction: 1,
                detail: "Game depot ready in bottle",
                bytesPerSecond: 0,
                state: .finished
            )
        )
    }

    public static func cancelDepotDownload() {
        SteamCMDEngine.shared.cancel()
    }
}
