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
import WhiskyKit
import SemanticVersion

struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @Environment(BottleVM.self) private var bottleVM
    @Binding var showSetup: Bool

    @State private var selection: SidebarSelection? = .library
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)
    @State private var bottleFilter = ""
    @State private var currentEngineID = WineEngineRegistry.shared.current.identifier
    @State private var engineBusy = false
    @State private var engineError: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
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
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showSetup) {
            SetupView(showSetup: $showSetup, firstTime: false)
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: selectedBottleURL,
                         bottles: bottleVM.bottles)
        }
        .onChange(of: selection) { _, newValue in
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

            if let restored = selectedBottleURL,
               let bottle = bottleVM.bottles.first(where: { $0.url == restored && $0.isAvailable }) {
                selection = .bottle(bottle.url)
            } else {
                selection = .library
            }

            if !WhiskyWineInstaller.isWhiskyWineInstalled() {
                showSetup = true
            }
            let task = Task.detached {
                return await WhiskyWineInstaller.shouldUpdateWhiskyWine()
            }
            let updateInfo = await task.value
            if updateInfo.0 {
                let alert = NSAlert()
                alert.messageText = String(localized: "update.whiskywine.title")
                alert.informativeText = String(format: String(localized: "update.whiskywine.description"),
                                               String(WhiskyWineInstaller.whiskyWineVersion()
                                                      ?? SemanticVersion(0, 0, 0)),
                                               String(updateInfo.1))
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.whiskywine.update"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    WhiskyWineInstaller.uninstall()
                    showSetup = true
                }
            }
        }
    }

    var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                Section("sidebar.discover") {
                    Label("sidebar.library", systemImage: "square.grid.2x2.fill")
                        .tag(SidebarSelection.library)
                    Label("sidebar.activity", systemImage: "waveform.path.ecg")
                        .tag(SidebarSelection.activity)
                }
                Section("sidebar.bottles") {
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
                    }
                    .help("button.createBottle")

                    Button {
                        refreshBottles()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .rotationEffect(refreshAnimation)
                    }
                    .help("button.refresh")

                    Spacer()
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
            RecipeLibraryView()
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
            return bottleVM.bottles.sorted()
        }
        return bottleVM.bottles
            .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
            .sorted()
    }

    private func switchEngine(to identifier: String) {
        guard !engineBusy, identifier != currentEngineID else { return }
        engineBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                await MainActor.run { WhiskyApp.killBottles() }
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
