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

    @State private var selected: URL?
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var showBottleSelection: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)

    /// Stable marker URL for the Library sidebar row. Uses a scheme that
    /// doesn't collide with real bottle URLs (which are `file://`).
    private static let libraryMarker: URL = {
        guard let url = URL(string: "macbottle://library") else {
            preconditionFailure("static library marker URL")
        }
        return url
    }()

    @State private var bottleFilter = ""
    @State private var currentEngineID = WineEngineRegistry.shared.current.identifier

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StatusPill(
                    title: MacBottleTheme.engineLabel(for: currentEngineID),
                    systemImage: "cpu",
                    color: MacBottleTheme.engineColor(for: currentEngineID)
                )
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
                         currentBottle: selected,
                         bottles: bottleVM.bottles)
        }
        .onChange(of: selected) {
            // Library marker is ephemeral; persist only real bottle URLs
            // so relaunches restore the user's last bottle choice and
            // fall back to Library when none was open.
            if selected == Self.libraryMarker {
                selectedBottleURL = nil
            } else {
                selectedBottleURL = selected
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .onReceive(NotificationCenter.default.publisher(for: WineEngineRegistry.engineDidChangeNotification)) { _ in
            currentEngineID = WineEngineRegistry.shared.current.identifier
        }
        .task {
            bottleVM.loadBottles()
            bottlesLoaded = true
            currentEngineID = WineEngineRegistry.shared.current.identifier

            // MacBottle: default to the Game Library unless the user has
            // an explicit bottle selection restored from a prior session.
            if let restored = selectedBottleURL,
               bottleVM.bottles.contains(where: { $0.url == restored && $0.isAvailable }) {
                selected = restored
            } else {
                selected = Self.libraryMarker
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
            List(selection: $selected) {
                Section("sidebar.discover") {
                    Label("sidebar.library", systemImage: "square.grid.2x2.fill")
                        .tag(Self.libraryMarker)
                }
                Section("sidebar.bottles") {
                    ForEach(filteredBottles) { bottle in
                        Group {
                            if bottle.inFlight {
                                HStack(spacing: 8) {
                                    Image(systemName: "shippingbox")
                                        .foregroundStyle(.secondary)
                                    Text(bottle.settings.name)
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                                .opacity(0.5)
                            } else {
                                BottleListEntry(bottle: bottle, selected: $selected, refresh: $triggerRefresh)
                                    .selectionDisabled(!bottle.isAvailable)
                            }
                        }
                        .id(bottle.url)
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
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    selected = url
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if selected == Self.libraryMarker {
            RecipeLibraryView()
        } else if let selectedURL = selected {
            if let bottle = bottleVM.bottles.first(where: { $0.url == selectedURL }) {
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
        } else {
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
            bottleVM.bottles
                .sorted()
        } else {
            bottleVM.bottles
                .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
                .sorted()
        }
    }

    private func refreshBottles() {
        bottleVM.loadBottles()
        if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
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
