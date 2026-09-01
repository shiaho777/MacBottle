//
//  SettingsView.swift
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

import SemanticVersion
import SwiftUI
import WhiskyKit

struct SettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") var whiskyUpdate = true
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("checkWhiskyWineUpdates") var checkWhiskyWineUpdates = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir

    @State private var selectedEngineID = WineEngineRegistry.shared.current.identifier
    @State private var engineBusy = false
    @State private var engineMessage: String?
    @State private var autoSelectEngine = LaunchEnginePolicy.autoSelectEnabled
    @State private var engineDescriptions: [String: String] = [:]

    var body: some View {
        Form {
            Section("settings.general") {
                Toggle("settings.toggle.kill.on.terminate", isOn: $killOnTerminate)
                ActionView(
                    text: "settings.path",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            defaultBottleLocation = url
                        }
                    }
                }
            }

            Section("settings.engine.section") {
                Toggle("settings.engine.autoSelect", isOn: $autoSelectEngine)
                    .onChange(of: autoSelectEngine) { _, newValue in
                        LaunchEnginePolicy.autoSelectEnabled = newValue
                    }
                Text("settings.engine.autoSelect.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("settings.engine.current", selection: $selectedEngineID) {
                    ForEach(WineEngineCatalog.allEngines().map(\.identifier), id: \.self) { id in
                        Text(engineDescriptions[id] ?? id).tag(id)
                    }
                }
                .disabled(engineBusy)
                .onChange(of: selectedEngineID) { _, newValue in
                    switchEngine(to: newValue, installIfNeeded: false)
                }

                Text("settings.engine.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let engineMessage {
                    Text(engineMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(
                        engineBusy
                            ? String(localized: "settings.engine.busy")
                            : String(localized: "settings.engine.installD3DMetal")
                    ) {
                        installD3DMetalEngine()
                    }
                    .disabled(engineBusy)

                    Button(
                        engineBusy
                            ? String(localized: "settings.engine.busy")
                            : String(localized: "settings.engine.importArm64")
                    ) {
                        importArm64Engine()
                    }
                    .disabled(engineBusy)

                    Button("settings.engine.refresh") {
                        refreshEngineDescriptions()
                    }
                    .disabled(engineBusy)
                }
            }

            Section("settings.section.update") {
                Toggle("settings.toggle.whisky.updates", isOn: $whiskyUpdate)
                Toggle("settings.toggle.whiskywine.updates", isOn: $checkWhiskyWineUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560)
        .navigationTitle("settings.general")
        .onAppear {
            selectedEngineID = WineEngineRegistry.shared.current.identifier
            refreshEngineDescriptions()
        }
    }

    private func refreshEngineDescriptions() {
        var map: [String: String] = [:]
        for engine in WineEngineCatalog.allEngines() {
            map[engine.identifier] = WineEngineCatalog.describe(engine)
        }
        engineDescriptions = map
    }

    private func switchEngine(to identifier: String, installIfNeeded: Bool) {
        engineBusy = true
        engineMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                await MainActor.run {
                    WhiskyApp.killBottles()
                }
                let engine = try WineEngineRegistry.shared.select(
                    identifier: identifier,
                    installIfNeeded: installIfNeeded
                )
                await MainActor.run {
                    selectedEngineID = engine.identifier
                    engineMessage = String(format: String(localized: "settings.engine.switched %@"), engine.displayName)
                    engineBusy = false
                    refreshEngineDescriptions()
                }
            } catch {
                await MainActor.run {
                    selectedEngineID = WineEngineRegistry.shared.current.identifier
                    engineMessage = error.localizedDescription
                    engineBusy = false
                    refreshEngineDescriptions()
                }
            }
        }
    }

    private func installD3DMetalEngine() {
        engineBusy = true
        engineMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let engine = try WineEngineCatalog.ensureD3DMetalEngine(force: false)
                _ = try WineEngineRegistry.shared.select(
                    identifier: engine.identifier,
                    installIfNeeded: false
                )
                await MainActor.run {
                    selectedEngineID = engine.identifier
                    let format = String(localized: "settings.engine.d3dmetalReady %@")
                    engineMessage = String(format: format, engine.libraryRoot.path)
                    engineBusy = false
                    refreshEngineDescriptions()
                }
            } catch {
                await MainActor.run {
                    engineMessage = error.localizedDescription
                    engineBusy = false
                    refreshEngineDescriptions()
                }
            }
        }
    }

    private func importArm64Engine() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gzip, .archive, .folder, .data]
        panel.message = String(localized: "settings.engine.importArm64.panel")
        panel.prompt = String(localized: "settings.engine.importArm64.prompt")
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            engineBusy = true
            engineMessage = nil
            Task.detached(priority: .userInitiated) {
                do {
                    let engine = WineEngineCatalog.arm64Engine()
                    var isDirectory: ObjCBool = false
                    let isDir = FileManager.default.fileExists(
                        atPath: url.path(percentEncoded: false),
                        isDirectory: &isDirectory
                    ) && isDirectory.boolValue
                    let isTarball = !isDir
                    if isDir {
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
                        WhiskyApp.killBottles()
                        selectedEngineID = engine.identifier
                        let format = String(localized: "settings.engine.imported %@")
                        engineMessage = String(format: format, engine.libraryRoot.path)
                        engineBusy = false
                        refreshEngineDescriptions()
                    }
                } catch {
                    await MainActor.run {
                        engineMessage = error.localizedDescription
                        engineBusy = false
                        refreshEngineDescriptions()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
