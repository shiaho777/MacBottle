//
//  ContentView.swift
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
import UniformTypeIdentifiers
import MacBottleKit
import SemanticVersion

struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @Environment(BottleVM.self) private var bottleVM
    @Environment(\.openSettings) private var openSettings
    @Binding var showSetup: Bool

    @State private var selection: SidebarSelection? = .library
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)
    @State private var bottleFilter = ""
    @State private var libraryResetToken = Int(Date().timeIntervalSince1970)
    @State private var currentEngineID = WineEngineRegistry.shared.current.identifier
    @State private var engineBusy = false
    @State private var engineError: String?
    @State private var setupStartsAtDownload = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            if !selectionIsBottle {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(WineEngineCatalog.allEngines(), id: \.identifier) { engine in
                            Button {
                                switchEngine(to: engine.identifier)
                            } label: {
                                if engine.identifier == currentEngineID {
                                    Label(WineEngineCatalog.describe(engine), systemImage: "checkmark")
                                } else {
                                    Text(WineEngineCatalog.describe(engine))
                                }
                            }
                        }
                    } label: {
                        if engineBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            StatusPill(
                                title: MacBottleTheme.engineLabel(for: currentEngineID),
                                systemImage: "cpu",
                                color: MacBottleTheme.engineColor(for: currentEngineID)
                            )
                        }
                    }
                    .help("toolbar.engine.help")
                }
                ToolbarItem(placement: .primaryAction) {
                    RecipeSyncToolbarButton()
                }
            }
        }
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showSetup, onDismiss: resetSetupStart) {
            SetupView(
                showSetup: $showSetup,
                firstTime: false,
                initialPath: setupStartsAtDownload ? [.engineDownload] : []
            )
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: selectedBottleURL,
                         bottles: bottleVM.bottles)
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .library {
                libraryResetToken += 1
            }
            #if DEBUG
            if Self.qaRoute != nil { return }
            #endif
            switch newValue {
            case .bottle(let url):
                selectedBottleURL = url
            default:
                selectedBottleURL = nil
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .onReceive(NotificationCenter.default.publisher(for: WineEngineRegistry.engineDidChangeNotification)) { _ in
            currentEngineID = WineEngineRegistry.shared.current.identifier
        }
        .onReceive(NotificationCenter.default.publisher(for: .macbottleNewBottle)) { _ in
            showBottleCreation = true
        }
        .alert(
            String(localized: "toolbar.engine.error.title"),
            isPresented: Binding(get: { engineError != nil }, set: { if !$0 { engineError = nil } })
        ) {
            Button("OK") { engineError = nil }
        } message: {
            if let engineError { Text(engineError) }
        }
        .task {
            bottleVM.loadBottles()
            bottlesLoaded = true
            currentEngineID = WineEngineRegistry.shared.current.identifier

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-settings") {
                try? await Task.sleep(for: .milliseconds(600))
                openSettings()
            }
            #endif

            if let route = Self.qaRoute {
                selection = route
            } else if let restored = selectedBottleURL,
                      let bottle = bottleVM.bottles.first(where: {
                          $0.isAvailable && Self.canonicalPath($0.url) == Self.canonicalPath(restored)
                      }) {
                selection = .bottle(bottle.url)
            } else {
                selection = .library
            }

            if !EngineInstaller.isEngineInstalled() {
                showSetup = true
            }
            let task = Task.detached {
                return await EngineInstaller.shouldUpdateEngine()
            }
            let updateInfo = await task.value
            if updateInfo.0 {
                let alert = NSAlert()
                alert.messageText = String(localized: "update.whiskywine.title")
                alert.informativeText = String(format: String(localized: "update.whiskywine.description"),
                                               String(EngineInstaller.engineVersion()
                                                      ?? SemanticVersion(0, 0, 0)),
                                               String(updateInfo.1))
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.whiskywine.update"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    setupStartsAtDownload = true
                    showSetup = true
                }
            }
        }
    }

    private func resetSetupStart() {
        setupStartsAtDownload = false
    }

    var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                Section {
                    HStack {
                        Text("sidebar.discover")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .selectionDisabled(true)
                    Label("sidebar.library", systemImage: "square.grid.2x2.fill")
                        .tag(SidebarSelection.library)
                    Label("sidebar.activity", systemImage: "waveform.path.ecg")
                        .tag(SidebarSelection.activity)
                }
                Section {
                    HStack {
                        Text("sidebar.bottles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .selectionDisabled(true)
                    ForEach(filteredBottles) { bottle in
                        if bottle.inFlight {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(.secondary)
                                Text(bottle.settings.name)
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                            .opacity(0.5)
                            .tag(SidebarSelection.bottle(bottle.url))
                            .id(bottle.url)
                        } else {
                            BottleListEntry(
                                bottle: bottle,
                                selection: $selection,
                                refresh: $triggerRefresh
                            )
                            .selectionDisabled(!bottle.isAvailable)
                            .tag(SidebarSelection.bottle(bottle.url))
                            .id(bottle.url)
                        }
                    }
                }
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: bottleFilter)
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .searchable(text: $bottleFilter, placement: .sidebar, prompt: "sidebar.bottles.search")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Button {
                        showBottleCreation.toggle()
                    } label: {
                        Label("button.createBottle", systemImage: "plus")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .help("button.createBottle")

                    Button {
                        refreshBottles()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .rotationEffect(refreshAnimation)
                    }
                    .help("button.refresh")
                    .accessibilityLabel(Text("button.refresh"))

                    Spacer()

                    SettingsLink {
                        Label("settings.title", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("settings.open")
                    .accessibilityLabel(Text("settings.title"))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .onChange(of: newlyCreatedBottleURL) { _, url in
                guard let url else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    selection = .bottle(url)
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        switch selection {
        case .library?:
            RecipeLibraryView(resetToken: libraryResetToken)
        case .activity?:
            ActivityCenterView(selection: $selection)
        case .bottle(let url)?:
            if let bottle = bottleVM.bottles.first(where: { $0.url == url }) {
                BottleView(bottle: bottle)
                    .disabled(bottle.inFlight)
                    .id(bottle.url)
            } else {
                EmptyStateCard(
                    systemImage: "questionmark.folder",
                    title: "bottle.unavailable.title",
                    message: "bottle.unavailable.message"
                )
            }
        case nil:
            if (bottleVM.bottles.isEmpty || bottleVM.countActive() == 0) && bottlesLoaded {
                EmptyStateCard(
                    systemImage: "shippingbox.and.arrow.backward",
                    title: "main.createFirst",
                    message: "main.createFirst.message",
                    actionTitle: "button.createBottle"
                ) {
                    showBottleCreation.toggle()
                }
            } else {
                EmptyStateCard(
                    systemImage: "sidebar.left",
                    title: "main.pickSidebar.title",
                    message: "main.pickSidebar.message"
                )
            }
        }
    }

    var filteredBottles: [Bottle] {
        if bottleFilter.isEmpty {
            return bottleVM.bottles.sorted(by: Bottle.nameOrder)
        }
        return bottleVM.bottles
            .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
            .sorted(by: Bottle.nameOrder)
    }

    private var selectionIsBottle: Bool {
        if case .bottle = selection {
            return true
        }
        return false
    }

    private static func canonicalPath(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).expandingTildeInPath
    }

    private static var qaRoute: SidebarSelection? {
        #if DEBUG
        let prefix = "--ui-route="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        switch argument.dropFirst(prefix.count) {
        case "library": return .library
        case "activity": return .activity
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private func confirmEngineSwitch() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "settings.engine.switch.confirm.title")
        alert.informativeText = String(localized: "settings.engine.switch.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "settings.engine.switch.confirm.action"))
        alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func switchEngine(to identifier: String) {
        guard !engineBusy, identifier != currentEngineID else { return }
        guard confirmEngineSwitch() else { return }
        engineBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                await MainActor.run { MacBottleApp.killBottles() }
                let engine = try WineEngineRegistry.shared.select(
                    identifier: identifier,
                    installIfNeeded: true
                )
                await MainActor.run {
                    ProgramLaunchCoordinator.shared.invalidateEngineBoundState()
                    engineBusy = false
                    currentEngineID = engine.identifier
                }
            } catch {
                await MainActor.run {
                    engineBusy = false
                    engineError = error.localizedDescription
                }
            }
        }
    }

    private func refreshBottles() {
        bottleVM.loadBottles()
        if case .bottle(let url)? = selection,
           let bottle = bottleVM.bottles.first(where: { $0.url == url }) {
            bottle.updateInstalledPrograms()
        }
        triggerRefresh.toggle()
        withAnimation(.default) {
            refreshAnimation = .degrees(360)
        } completion: {
            refreshAnimation = .degrees(0)
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environment(BottleVM.shared)
}

extension Notification.Name {
    static let macbottleNewBottle = Notification.Name("app.macbottle.newBottle")
}
