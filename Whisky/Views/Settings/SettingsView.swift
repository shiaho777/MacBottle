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
            Section("通用") {
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

            Section("Wine 引擎") {
                Toggle("启动时按游戏自动选择引擎", isOn: $autoSelectEngine)
                    .onChange(of: autoSelectEngine) { _, newValue in
                        LaunchEnginePolicy.autoSelectEnabled = newValue
                    }
                Text("配方 renderer / PE 导入表会在启动瞬间临时切换引擎，不覆盖你的手动选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("当前引擎", selection: $selectedEngineID) {
                    ForEach(WineEngineCatalog.allEngines().map(\.identifier), id: \.self) { id in
                        Text(engineDescriptions[id] ?? id).tag(id)
                    }
                }
                .disabled(engineBusy)
                .onChange(of: selectedEngineID) { _, newValue in
                    switchEngine(to: newValue, installIfNeeded: false)
                }

                Text("Modern：Wine 11.x 通用栈。D3DMetal：旧 CrossOver 栈，64 位 D3D11/12 更强。切换后请重开游戏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let engineMessage {
                    Text(engineMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(engineBusy ? "处理中…" : "安装 / 修复 D3DMetal 引擎") {
                        installD3DMetalEngine()
                    }
                    .disabled(engineBusy)

                    Button("刷新状态") {
                        refreshEngineDescriptions()
                    }
                    .disabled(engineBusy)
                }
            }

            Section("更新") {
                Toggle("settings.toggle.whisky.updates", isOn: $whiskyUpdate)
                Toggle("settings.toggle.whiskywine.updates", isOn: $checkWhiskyWineUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560)
        .navigationTitle("设置")
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
                    engineMessage = "已切换到 \(engine.displayName)"
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
                    engineMessage = "D3DMetal 引擎已就绪：\(engine.libraryRoot.path)"
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

#Preview {
    SettingsView()
}
