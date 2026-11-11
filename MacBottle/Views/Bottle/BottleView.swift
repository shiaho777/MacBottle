//
//  BottleView.swift
//  MacBottle
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
import SwiftUI
import UniformTypeIdentifiers
import MacBottleKit

enum BottleTab: String, CaseIterable, Identifiable {
    case overview
    case games
    case settings
    case activity

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: return "bottle.tab.overview"
        case .games: return "bottle.tab.games"
        case .settings: return "bottle.tab.settings"
        case .activity: return "bottle.tab.activity"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "house"
        case .games: return "gamecontroller"
        case .settings: return "slider.horizontal.3"
        case .activity: return "waveform.path.ecg"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: return "1"
        case .games: return "2"
        case .settings: return "3"
        case .activity: return "4"
        }
    }
}

struct BottleView: View {
    @Bindable var bottle: Bottle
    @State private var launchCoordinator = ProgramLaunchCoordinator.shared
    @State private var path = NavigationPath()
    @State private var tab: BottleTab = BottleView.initialTab
    @State private var selectedProgramURL: URL?
    @State private var showWinetricksSheet = false
    @State private var showWorkspaceImport = false
    @State private var showForceStopConfirm = false
    @State private var programLoading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gridLayout = [
        GridItem(.adaptive(minimum: 112, maximum: 140), spacing: MacBottleTheme.gridSpacing)
    ]

    private static var initialTab: BottleTab {
        #if DEBUG
        let prefix = "--ui-tab="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
           let tab = BottleTab(rawValue: String(argument.dropFirst(prefix.count))) {
            return tab
        }
        #endif
        return .overview
    }

    private var recentPrograms: [Program] {
        bottle.programs
            .filter { $0.settings.lastLaunchedAt != nil }
            .sorted {
                ($0.settings.lastLaunchedAt ?? .distantPast)
                    > ($1.settings.lastLaunchedAt ?? .distantPast)
            }
            .prefix(5)
            .map { $0 }
    }

    private var primaryProgram: Program? {
        if let selectedProgramURL,
           let selected = bottle.programs.first(where: { $0.url == selectedProgramURL }) {
            return selected
        }
        if let recent = recentPrograms.first {
            return recent
        }
        return bottle.pinnedPrograms.first?.program
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                BottleTabBar(selection: $tab)
                Divider()
                    .opacity(0.55)
                selectedTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppBackground())
            .navigationTitle(bottle.settings.name)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .sheet(isPresented: $showWorkspaceImport) {
                WorkspaceImportView(bottle: bottle)
            }
            .alert("bottle.forceStop.confirm.title", isPresented: $showForceStopConfirm) {
                Button("bottle.forceStop.confirm.action", role: .destructive) {
                    BottleForceStop.forceStop(bottle: bottle, reason: "toolbar")
                }
                Button("button.removeAlert.cancel", role: .cancel) {}
            } message: {
                Text("bottle.forceStop.confirm.message")
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
            .onAppear {
                Task { await refreshProgramsIfNeeded() }
                if selectedProgramURL == nil {
                    selectedProgramURL = bottle.pinnedPrograms.first?.program.url
                }
                Task(priority: .utility) {
                    await Wine.ensureBottleReady(bottle)
                }
            }
            .onChange(of: bottle.pinnedPrograms.map(\.program.url)) { _, urls in
                guard !urls.contains(where: { $0 == selectedProgramURL }) else { return }
                selectedProgramURL = urls.first
            }
            .disabled(!bottle.isAvailable)
        }
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch tab {
        case .overview:
            overviewTab
        case .games:
            ProgramsView(bottle: bottle, path: $path, browsePrograms: runExternalProgram)
        case .settings:
            ConfigView(bottle: bottle)
        case .activity:
            BottleActivityTab(bottle: bottle)
        }
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacBottleTheme.sectionSpacing) {
                launchStatusBanner
                BottleHeroHeader(bottle: bottle)
                metricsGrid
                continuePlayingCard

                if !bottle.pinnedPrograms.isEmpty {
                    pinnedSection
                }

                if !recentPrograms.isEmpty {
                    recentSection
                }

                if bottle.pinnedPrograms.isEmpty && recentPrograms.isEmpty {
                    BottleOnboardingCard(
                        browsePrograms: runExternalProgram,
                        openGames: { tab = .games }
                    )
                }
            }
            .padding(MacBottleTheme.pagePadding)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
            spacing: 10
        ) {
            MetricTile(
                title: "bottle.metrics.programs",
                value: "\(bottle.programs.count)",
                systemImage: "app.fill",
                tint: .blue
            )
            MetricTile(
                title: "bottle.metrics.pins",
                value: "\(bottle.pinnedPrograms.count)",
                systemImage: "pin.fill",
                tint: .orange
            )
            MetricTile(
                title: "bottle.metrics.windows",
                value: bottle.settings.windowsVersion.pretty(),
                systemImage: "desktopcomputer",
                tint: .teal
            )
            MetricTile(
                title: "bottle.metrics.engine",
                value: MacBottleTheme.engineLabel(for: bottle.settings.engineID),
                systemImage: "cpu",
                tint: .purple
            )
        }
    }

    @ViewBuilder
    private var continuePlayingCard: some View {
        if let program = primaryProgram {
            SurfaceCard(padding: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: MacBottleTheme.tileRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("bottle.continue.title")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(program.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        if let date = program.settings.lastLaunchedAt {
                            Text(
                                Self.relativeFormatter.localizedString(
                                    for: date,
                                    relativeTo: Date()
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        selectedProgramURL = program.url
                        program.run()
                    } label: {
                        Label("bottle.continue.play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: MacBottleTheme.rowSpacing) {
            SectionHeader(
                title: "bottle.section.pinned",
                trailingTitle: "bottle.section.allGames"
            ) {
                tab = .games
            }
            LazyVGrid(columns: gridLayout, alignment: .leading, spacing: MacBottleTheme.gridSpacing) {
                ForEach(bottle.pinnedPrograms, id: \.id) { pinned in
                    PinView(
                        bottle: bottle,
                        program: pinned.program,
                        pin: pinned.pin,
                        path: $path,
                        isSelected: selectedProgramURL == pinned.program.url,
                        onSelect: { selectedProgramURL = pinned.program.url }
                    )
                }
                PinAddView(bottle: bottle)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: MacBottleTheme.rowSpacing) {
            SectionHeader(
                title: "bottle.section.recent",
                trailingTitle: "bottle.section.allGames"
            ) {
                tab = .games
            }
            VStack(spacing: 8) {
                ForEach(recentPrograms, id: \.id) { program in
                    RecentProgramRow(program: program, path: $path)
                }
            }
        }
    }

    private var toolbarContent: some ToolbarContent {
        Group {
            if tab != .games {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let program = primaryProgram {
                            selectedProgramURL = program.url
                            program.run()
                        } else {
                            runExternalProgram()
                        }
                    } label: {
                        Label(primaryActionTitle, systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .disabled(programLoading || !bottle.isAvailable)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("bottle.manage.programs.title", systemImage: "list.bullet.rectangle") {
                        tab = .games
                    }
                    Button("bottle.manage.config.title", systemImage: "slider.horizontal.3") {
                        tab = .settings
                    }
                    Button("bottle.manage.logs.title", systemImage: "doc.text") {
                        tab = .activity
                    }
                    Divider()
                    Button("bottle.bar.cDrive", systemImage: "internaldrive") {
                        bottle.openCDrive()
                    }
                    Button("bottle.bar.terminal", systemImage: "terminal") {
                        bottle.openTerminal()
                    }
                    Button("bottle.menu.winetricks", systemImage: "wrench.and.screwdriver") {
                        showWinetricksSheet = true
                    }
                    Button("workspace.import.title", systemImage: "tray.and.arrow.down") {
                        showWorkspaceImport = true
                    }
                    Divider()
                    Button("bottle.bar.forceStop", systemImage: "xmark.octagon", role: .destructive) {
                        showForceStopConfirm = true
                    }
                } label: {
                    Label("bottle.more", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var primaryActionTitle: String {
        guard let program = primaryProgram else {
            return String(localized: "bottle.empty.action")
        }
        return String(format: String(localized: "bottle.continue.playSelected %@"), program.name)
    }

    private func refreshPrograms() async {
        await bottle.refreshInstalledPrograms()
    }

    /// A full prefix walk is expensive on large bottles (Steam libraries
    /// can hold thousands of files). Only rescan when the cached result
    /// is stale; the Programs tab's Refresh button still forces one.
    private func refreshProgramsIfNeeded() async {
        guard bottle.needsProgramScan() else { return }
        await bottle.refreshInstalledPrograms()
    }

    private func runExternalProgram() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "exe") ?? .data,
            UTType(filenameExtension: "msi") ?? .data
        ].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.message = String(localized: "bottle.run.panel.message")
        panel.prompt = String(localized: "bottle.run.panel.prompt")

        panel.begin { result in
            guard result == .OK, let selected = panel.url else { return }
            programLoading = true
            Task(priority: .userInitiated) {
                defer {
                    Task { @MainActor in programLoading = false }
                }
                do {
                    let launchURL = try prepareLaunchURL(selected)
                    if launchURL.pathExtension.lowercased() == "bat"
                        || launchURL.pathExtension.lowercased() == "cmd" {
                        try await Wine.runBatchFile(url: launchURL, bottle: bottle)
                    } else {
                        try await Wine.runProgram(
                            at: launchURL,
                            bottle: bottle,
                            wait: false,
                            applyDXVK: false
                        )
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "bottle.run.info.failed.title")
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }

    private func prepareLaunchURL(_ url: URL) throws -> URL {
        let bottlePath = bottle.url.path
        if url.path.hasPrefix(bottlePath) {
            return url
        }

        let imports = bottle.url
            .appending(path: "drive_c")
            .appending(path: "MacBottleImports")
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)

        var destName = url.lastPathComponent
        if destName.unicodeScalars.contains(where: { !$0.isASCII }) {
            let ext = url.pathExtension
            destName = "import_\(Int(Date().timeIntervalSince1970))"
            if !ext.isEmpty { destName += ".\(ext)" }
        }
        let destination = imports.appending(path: destName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    // MARK: - Launch status banner

    private var isLaunchBannerForCurrentBottle: Bool {
        guard let activeBottleURL = launchCoordinator.activeBottleURL else {
            return false
        }
        return activeBottleURL.standardizedFileURL == bottle.url.standardizedFileURL
    }

    @ViewBuilder
    private var launchStatusBanner: some View {
        if isLaunchBannerForCurrentBottle {
            scopedLaunchStatusBanner
        }
    }

    @ViewBuilder
    private var scopedLaunchStatusBanner: some View {
        switch launchCoordinator.phase {
        case .idle:
            EmptyView()
        case .warming(let bottleName):
            launchBanner(
                tint: .blue,
                systemImage: "flame.fill",
                title: String(localized: "bottle.launch.warming"),
                message: String(format: String(localized: "bottle.launch.warming.message %@"), bottleName),
                showsProgress: true
            )
        case .provisioning(let programName, let detail):
            launchBanner(
                tint: .blue,
                systemImage: "shippingbox.fill",
                title: String(localized: "bottle.launch.provisioning"),
                message: "\(programName) · \(detail)",
                showsProgress: true
            )
        case .launching(let programName, _):
            launchBanner(
                tint: .accentColor,
                systemImage: "play.circle.fill",
                title: String(localized: "bottle.launch.launching"),
                message: programName,
                showsProgress: true
            )
        case .launched(let programName):
            launchBanner(
                tint: .green,
                systemImage: "checkmark.circle.fill",
                title: String(localized: "bottle.launch.launched"),
                message: programName,
                showsProgress: false
            )
        case .failed(let programName, let message):
            launchBanner(
                tint: .red,
                systemImage: "exclamationmark.triangle.fill",
                title: String(format: String(localized: "bottle.launch.failed %@"), programName),
                message: message,
                showsProgress: false,
                showsLogLink: true
            )
        }
    }

    @ViewBuilder
    private func launchBanner(
        tint: Color,
        systemImage: String,
        title: String,
        message: String,
        showsProgress: Bool,
        showsLogLink: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if showsLogLink {
                Button("bottle.launch.viewLogs") {
                    tab = .activity
                }
                .buttonStyle(.borderless)
            }
            if case .failed = launchCoordinator.phase {
                Button("bottle.launch.close") {
                    launchCoordinator.dismiss()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                .fill(tint.opacity(MacBottleTheme.tintFillOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                .strokeBorder(tint.opacity(MacBottleTheme.tintBorderOpacity), lineWidth: 1)
        }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: launchCoordinator.phase)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
}

struct BottleActivityTab: View {
    @Bindable var bottle: Bottle
    @State private var pane: ActivityPane = BottleActivityTab.initialPane

    private static var initialPane: ActivityPane {
        #if DEBUG
        let prefix = "--ui-activity="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
           let pane = ActivityPane(rawValue: String(argument.dropFirst(prefix.count))) {
            return pane
        }
        #endif
        return .processes
    }

    enum ActivityPane: String, CaseIterable, Identifiable {
        case processes
        case logs
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .processes: return "bottle.activity.processes"
            case .logs: return "bottle.activity.logs"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("bottle.activity", selection: $pane) {
                ForEach(ActivityPane.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, MacBottleTheme.pagePadding)
            .padding(.vertical, 10)
            Divider()
            switch pane {
            case .processes:
                RunningProcessesView(bottle: bottle)
            case .logs:
                ProgramLogsView(bottle: bottle)
            }
        }
    }
}

private struct BottleTabBar: View {
    @Binding var selection: BottleTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BottleTab.allCases) { tab in
                Button {
                    withAnimation(AppMotion.standard) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.subheadline.weight(selection == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                                .matchedGeometryEffect(id: "bottleTab", in: namespace)
                        }
                    }
                    .overlay {
                        if selection == tab {
                            Capsule()
                                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, MacBottleTheme.pagePadding)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct BottleOnboardingCard: View {
    let browsePrograms: () -> Void
    let openGames: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                .shadow(color: Color.accentColor.opacity(0.24), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text("bottle.empty.title")
                        .font(.title3.weight(.bold))
                    Text("bottle.empty.message")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                step(number: "1", title: "bottle.empty.step.install", tint: .orange)
                step(number: "2", title: "bottle.empty.step.pin", tint: .pink)
                step(number: "3", title: "bottle.empty.step.play", tint: .green)
            }

            HStack(spacing: 10) {
                Button("bottle.empty.action") {
                    browsePrograms()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(.large)

                Button("bottle.tab.games") {
                    openGames()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .fill(.background.secondary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
        }
    }

    private func step(number: String, title: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint, in: Circle())
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

private struct RecentProgramRow: View {
    @Bindable var program: Program
    @Binding var path: NavigationPath
    @State private var launchCoordinator = ProgramLaunchCoordinator.shared

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: program.pinned ? "pin.fill" : "clock.arrow.circlepath")
                .foregroundStyle(program.pinned ? .orange : .teal)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(program.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let date = program.settings.lastLaunchedAt {
                    Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("bottle.recent.configure") {
                path.append(program)
            }
            .buttonStyle(.borderless)
            if launchCoordinator.isLaunching(programURL: program.url) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    program.run()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("programs.run")
                .accessibilityLabel(Text("programs.run"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                .fill(.background.secondary)
        }
        .opacity(launchCoordinator.isLaunching(programURL: program.url) ? 0.75 : 1)
    }
}
