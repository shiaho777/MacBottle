//
//  ConfigView.swift
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
import Metal
import WhiskyKit
import os.log

enum LoadingState {
    case loading
    case modifying
    case success
    case failed
}

struct ConfigView: View {
    private var bottleEngineSelection: Binding<String> {
        Binding(
            get: { bottle.settings.engineID ?? LaunchEnginePolicy.autoEngineToken },
            set: { newValue in
                bottle.settings.engineID = (newValue == LaunchEnginePolicy.autoEngineToken) ? nil : newValue
            }
        )
    }

    @Bindable var bottle: Bottle
    @State private var buildVersion: Int = 0
    @State private var retinaMode: Bool = false
    @State private var dpiConfig: Int = 96
    @State private var winVersionLoadingState: LoadingState = .loading
    @State private var buildVersionLoadingState: LoadingState = .loading
    @State private var retinaModeLoadingState: LoadingState = .loading
    @State private var dpiConfigLoadingState: LoadingState = .loading
    @State private var dpiSheetPresented: Bool = false
    @AppStorage("wineSectionExpanded") private var wineSectionExpanded: Bool = true
    @AppStorage("dxvkSectionExpanded") private var dxvkSectionExpanded: Bool = true
    @AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true
    @State private var d3dMetalStatus = D3DMetalCapability.probe()
    @State private var d3dMetalBusy = false

    var body: some View {
        Form {
            Section("config.title.wine", isExpanded: $wineSectionExpanded) {
                SettingItemView(title: "config.winVersion", loadingState: winVersionLoadingState) {
                    Picker("config.winVersion", selection: $bottle.settings.windowsVersion) {
                        ForEach(WinVersion.allCases.reversed(), id: \.self) {
                            Text($0.pretty())
                        }
                    }
                }
                SettingItemView(title: "config.buildVersion", loadingState: buildVersionLoadingState) {
                    TextField("config.buildVersion", value: $buildVersion, formatter: NumberFormatter())
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit {
                            buildVersionLoadingState = .modifying
                            Task(priority: .userInitiated) {
                                do {
                                    try await Wine.changeBuildVersion(bottle: bottle, version: buildVersion)
                                    buildVersionLoadingState = .success
                                } catch {
                                    Logger.uiLogger.error("Failed to change build version")
                                    buildVersionLoadingState = .failed
                                }
                            }
                        }
                }
                SettingItemView(title: "config.retinaMode", loadingState: retinaModeLoadingState) {
                    Toggle("config.retinaMode", isOn: $retinaMode)
                        .onChange(of: retinaMode, { _, newValue in
                            Task(priority: .userInitiated) {
                                retinaModeLoadingState = .modifying
                                do {
                                    try WineRegistryFile.setStringValue(
                                        bottle: bottle,
                                        keyPath: DisplayPolicy.macDriverKey,
                                        name: "RetinaMode",
                                        value: newValue ? "y" : "n"
                                    )
                                    try await Wine.changeRetinaMode(bottle: bottle, retinaMode: newValue)
                                    retinaModeLoadingState = .success
                                } catch {
                                    Logger.uiLogger.error("Failed to change retina mode")
                                    retinaModeLoadingState = .failed
                                }
                            }
                        })
                }
                Picker("config.enhancedSync", selection: $bottle.settings.enhancedSync) {
                    Text("config.enhancedSync.none").tag(EnhancedSync.none)
                    Text("config.enhacnedSync.esync").tag(EnhancedSync.esync)
                    Text("config.enhacnedSync.msync").tag(EnhancedSync.msync)
                }
                Picker("Wine 引擎绑定", selection: bottleEngineSelection) {
                    Text("自动（配方 / PE）").tag(LaunchEnginePolicy.autoEngineToken)
                    Text(WineEngineCatalog.describe(WineEngineCatalog.modernEngine()))
                        .tag(WineEngineCatalog.modernIdentifier)
                    Text(WineEngineCatalog.describe(WineEngineCatalog.d3dMetalEngine()))
                        .tag(WineEngineCatalog.d3dMetalIdentifier)
                }
                Text("仅对本容器生效。选「自动」时遵循全局自动策略；固定引擎会覆盖配方/PE 建议。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingItemView(title: "config.dpi", loadingState: dpiConfigLoadingState) {
                    Button("config.inspect") {
                        dpiSheetPresented = true
                    }
                    .sheet(isPresented: $dpiSheetPresented) {
                        DPIConfigSheetView(
                            dpiConfig: $dpiConfig,
                            isRetinaMode: $retinaMode,
                            presented: $dpiSheetPresented
                        )
                    }
                }
                if #available(macOS 15, *) {
                    Toggle(isOn: $bottle.settings.avxEnabled) {
                        VStack(alignment: .leading) {
                            Text("config.avx")
                            if bottle.settings.avxEnabled {
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .font(.subheadline)
                                    Text("config.avx.warning")
                                        .fontWeight(.light)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            Section("config.title.dxvk", isExpanded: $dxvkSectionExpanded) {
                Toggle(isOn: $bottle.settings.dxvk) {
                    Text("config.dxvk")
                }
                Toggle(isOn: $bottle.settings.dxvkAsync) {
                    Text("config.dxvk.async")
                }
                .disabled(!bottle.settings.dxvk)
                Picker("config.dxvkHud", selection: $bottle.settings.dxvkHud) {
                    Text("config.dxvkHud.full").tag(DXVKHUD.full)
                    Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                    Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                    Text("config.dxvkHud.off").tag(DXVKHUD.off)
                }
                .disabled(!bottle.settings.dxvk)
            }
            Section("config.title.metal", isExpanded: $metalSectionExpanded) {
                Toggle(isOn: $bottle.settings.metalHud) {
                    Text("config.metalHud")
                }
                Toggle(isOn: $bottle.settings.metalTrace) {
                    Text("config.metalTrace")
                    Text("config.metalTrace.info")
                }
                if let device = MTLCreateSystemDefaultDevice() {
                    if device.supportsFamily(.apple9) {
                        Toggle(isOn: $bottle.settings.dxrEnabled) {
                            Text("config.dxr")
                            Text("config.dxr.info")
                        }
                    }
                }
            }
            Section("D3DMetal / GPTK") {
                LabeledContent("状态") {
                    Text(d3dMetalStatus.summary)
                        .foregroundStyle(d3dMetalStatus.available ? .green : .secondary)
                }
                if d3dMetalStatus.linkedUnixModules {
                    Text("Unix d3d 模块已桥接，64 位 D3D11/12 可走 D3DMetal。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if d3dMetalStatus.available {
                    Text("已找到 D3DMetal，但当前 Wine 未链接 d3d11.so 桥。老 2D 游戏不受影响。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未检测到 D3DMetal。可从历史 WhiskyWine 备份恢复框架文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(d3dMetalBusy ? "处理中…" : "探测 / 恢复 D3DMetal") {
                    d3dMetalBusy = true
                    Task.detached(priority: .userInitiated) {
                        _ = try? D3DMetalCapability.restoreBundledIfPossible()
                        let status = D3DMetalCapability.probe()
                        await MainActor.run {
                            d3dMetalStatus = status
                            d3dMetalBusy = false
                        }
                    }
                }
                .disabled(d3dMetalBusy)
            }
        }
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: wineSectionExpanded)
        .animation(.whiskyDefault, value: dxvkSectionExpanded)
        .animation(.whiskyDefault, value: metalSectionExpanded)
        .bottomBar {
            HStack {
                Spacer()
                Button("config.controlPanel") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.control(bottle: bottle)
                        } catch {
                            Logger.uiLogger.error("Failed to launch control")
                        }
                    }
                }
                Button("config.regedit") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.regedit(bottle: bottle)
                        } catch {
                            Logger.uiLogger.error("Failed to launch regedit")
                        }
                    }
                }
                Button("config.winecfg") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.cfg(bottle: bottle)
                        } catch {
                            Logger.uiLogger.error("Failed to launch winecfg")
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("tab.config")
        .onAppear {
            winVersionLoadingState = .success

            loadBuildName()

            if DisplayPolicy.isRetinaEnabled(bottle: bottle) {
                retinaMode = true
                retinaModeLoadingState = .success
            } else if WineRegistryFile.stringValue(
                bottle: bottle,
                keyPath: DisplayPolicy.macDriverKey,
                name: "RetinaMode"
            ) == "n" {
                retinaMode = false
                retinaModeLoadingState = .success
            } else {
                Task(priority: .userInitiated) {
                    do {
                        retinaMode = try await Wine.retinaMode(bottle: bottle)
                        retinaModeLoadingState = .success
                    } catch {
                        Logger.uiLogger.error("ConfigView error: \(error.localizedDescription)")
                        retinaModeLoadingState = .failed
                    }
                }
            }
            d3dMetalStatus = D3DMetalCapability.probe()
            Task(priority: .userInitiated) {
                do {
                    dpiConfig = try await Wine.dpiResolution(bottle: bottle) ?? 0
                    dpiConfigLoadingState = .success
                } catch {
                    Logger.uiLogger.error("ConfigView error: \(error.localizedDescription)")
                    // If DPI has not yet been edited, there will be no registry entry
                    dpiConfigLoadingState = .success
                }
            }
        }
        .onChange(of: bottle.settings.windowsVersion) { _, newValue in
            if winVersionLoadingState == .success {
                winVersionLoadingState = .loading
                buildVersionLoadingState = .loading
                Task(priority: .userInitiated) {
                    do {
                        try await Wine.changeWinVersion(bottle: bottle, win: newValue)
                        winVersionLoadingState = .success
                        bottle.settings.windowsVersion = newValue
                        loadBuildName()
                    } catch {
                        Logger.uiLogger.error("ConfigView error: \(error.localizedDescription)")
                        winVersionLoadingState = .failed
                    }
                }
            }
        }
        .onChange(of: dpiConfig) {
            if dpiConfigLoadingState == .success {
                Task(priority: .userInitiated) {
                    dpiConfigLoadingState = .modifying
                    do {
                        try await Wine.changeDpiResolution(bottle: bottle, dpi: dpiConfig)
                        dpiConfigLoadingState = .success
                    } catch {
                        Logger.uiLogger.error("ConfigView error: \(error.localizedDescription)")
                        dpiConfigLoadingState = .failed
                    }
                }
            }
        }
    }

    func loadBuildName() {
        Task(priority: .userInitiated) {
            do {
                if let buildVersionString = try await Wine.buildVersion(bottle: bottle) {
                    buildVersion = Int(buildVersionString) ?? 0
                } else {
                    buildVersion = 0
                }

                buildVersionLoadingState = .success
            } catch {
                Logger.uiLogger.error("ConfigView error: \(error.localizedDescription)")
                buildVersionLoadingState = .failed
            }
        }
    }
}

struct DPIConfigSheetView: View {
    @Binding var dpiConfig: Int
    @Binding var isRetinaMode: Bool
    @Binding var presented: Bool
    @State var stagedChanges: Float
    @FocusState var textFocused: Bool

    init(dpiConfig: Binding<Int>, isRetinaMode: Binding<Bool>, presented: Binding<Bool>) {
        self._dpiConfig = dpiConfig
        self._isRetinaMode = isRetinaMode
        self._presented = presented
        self.stagedChanges = Float(dpiConfig.wrappedValue)
    }

    var body: some View {
        VStack {
            HStack {
                Text("configDpi.title")
                    .fontWeight(.bold)
                Spacer()
            }
            Divider()
            GroupBox(label: Label("configDpi.preview", systemImage: "text.magnifyingglass")) {
                VStack {
                    HStack {
                        Text("configDpi.previewText")
                            .padding(16)
                            .font(.system(size:
                                (10 * CGFloat(stagedChanges)) / 72 *
                                          (isRetinaMode ? 0.5 : 1)
                            ))
                        Spacer()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 80)
            }
            HStack {
                Slider(value: $stagedChanges, in: 96...480, step: 24, onEditingChanged: { _ in
                    textFocused = false
                })
                TextField(String(), value: $stagedChanges, format: .number)
                    .frame(width: 40)
                    .focused($textFocused)
                Text("configDpi.dpi")
            }
            Spacer()
            HStack {
                Spacer()
                Button("create.cancel") {
                    presented = false
                }
                .keyboardShortcut(.cancelAction)
                Button("button.ok") {
                    dpiConfig = Int(stagedChanges)
                    presented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: ViewWidth.medium, height: 240)
    }
}

struct SettingItemView<Content: View>: View {
    let title: String.LocalizationValue
    let loadingState: LoadingState
    @ViewBuilder var content: () -> Content

    @Namespace private var viewId
    @Namespace private var progressViewId

    var body: some View {
        HStack {
            Text(String(localized: title))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                switch loadingState {
                case .loading, .modifying:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .matchedGeometryEffect(id: progressViewId, in: viewId)
                case .success:
                    content()
                        .labelsHidden()
                        .disabled(loadingState != .success)
                case .failed:
                    Text("config.notAvailable")
                        .font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }.animation(.default, value: loadingState)
        }
    }
}
