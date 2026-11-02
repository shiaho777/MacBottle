//
//  WhiskyWineDownloadView.swift
//  Whisky
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

import AppKit
import SemanticVersion
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @State private var importError: String?
    @State private var importing = false
    @State private var canReuseLegacy = false
    @State private var downloadingFallback = false
    @State private var fallbackProgress: Double = 0
    @Binding var showSetup: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("setup.whiskywine.download")
                .font(.title)
                .fontWeight(.bold)
            Text("setup.whiskywine.download.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("setup.engine.fallback.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if downloadingFallback {
                ProgressView(value: min(max(fallbackProgress, 0), 1), total: 1)
                    .padding(.horizontal)
                Text("setup.engine.fallback.downloading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let importError {
                Text(verbatim: importError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if importing {
                ProgressView()
                    .controlSize(.small)
                Text("setup.engine.importing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if canReuseLegacy {
                    Button("setup.engine.reuseLegacy") {
                        reuseLegacyEngine()
                    }
                }
                Button("setup.engine.fallback") {
                    downloadFallback()
                }
                .buttonStyle(.borderedProminent)
                Button("setup.engine.import") {
                    importEngine()
                }
            }
        }
        .frame(width: 440, height: 280)
        .onAppear {
            canReuseLegacy = EngineRecovery.canRecover()
        }
    }

    private func downloadFallback() {
        let release = EngineFallbackCatalog.gcenxWine
        downloadingFallback = true
        fallbackProgress = 0
        importError = nil

        let destination = FileManager.default.temporaryDirectory
            .appending(path: "MacBottle-\(release.engineID)-\(UUID().uuidString).tar.xz")

        Task {
            do {
                try await EngineDownloadService.shared.download(
                    from: release.url,
                    to: destination,
                    expectedSHA256: release.sha256
                ) { progress in
                    Task { @MainActor in
                        fallbackProgress = progress.fraction
                    }
                }
                defer { try? FileManager.default.removeItem(at: destination) }

                let engine = WineEngineCatalog.gcenxEngine()
                try await EngineImportService.importGcenxTarball(
                    at: destination,
                    engine: engine,
                    fallbackVersion: SemanticVersion(11, 21, 0)
                )
                _ = try WineEngineRegistry.shared.select(
                    identifier: engine.identifier,
                    installIfNeeded: false
                )
                await MainActor.run {
                    ProgramLaunchCoordinator.shared.invalidateEngineBoundState()
                    showSetup = false
                }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                await MainActor.run {
                    importError = error.localizedDescription
                    downloadingFallback = false
                }
            }
        }
    }

    private func reuseLegacyEngine() {
        guard let source = EngineRecovery.legacyEngineRoot() else { return }
        importing = true
        importError = nil

        Task {
            do {
                let engine = CrossOverEngine.default
                try await EngineImportService.importFolder(
                    at: source,
                    into: engine.libraryRoot,
                    fallbackVersion: SemanticVersion(0, 0, 0)
                )
                _ = try WineEngineRegistry.shared.select(
                    identifier: engine.identifier,
                    installIfNeeded: false
                )
                await MainActor.run {
                    ProgramLaunchCoordinator.shared.invalidateEngineBoundState()
                    showSetup = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    importing = false
                }
            }
        }
    }

    private func importEngine() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gzip, .archive, .folder, .data]
        panel.message = String(localized: "setup.engine.import.panel")
        panel.prompt = String(localized: "setup.engine.import.prompt")
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            importing = true
            importError = nil

            Task {
                do {
                    let engine = WineEngineCatalog.arm64Engine()
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(
                        atPath: url.path(percentEncoded: false),
                        isDirectory: &isDirectory
                    )
                    if exists && isDirectory.boolValue {
                        try await EngineImportService.importFolder(
                            at: url,
                            into: engine.libraryRoot,
                            fallbackVersion: SemanticVersion(0, 0, 0)
                        )
                    } else {
                        try await EngineImportService.importTarball(
                            at: url,
                            engine: engine,
                            fallbackVersion: SemanticVersion(0, 0, 0)
                        )
                    }
                    _ = try WineEngineRegistry.shared.select(
                        identifier: engine.identifier,
                        installIfNeeded: false
                    )
                    await MainActor.run {
                        ProgramLaunchCoordinator.shared.invalidateEngineBoundState()
                        showSetup = false
                    }
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        importing = false
                    }
                }
            }
        }
    }
}
