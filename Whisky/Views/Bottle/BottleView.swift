//
//  BottleView.swift
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
import AppKit
import UniformTypeIdentifiers
import WhiskyKit

enum BottleStage {
    case config
    case programs
    case processes
    case logs
}

struct BottleView: View {
    @Bindable var bottle: Bottle
    @State private var launchCoordinator = ProgramLaunchCoordinator.shared
    @State private var path = NavigationPath()
    @State private var programLoading: Bool = false
    @State private var showWinetricksSheet: Bool = false
    @State private var showWorkspaceImport: Bool = false
    @State private var selectedProgramURL: URL?

    private let gridLayout = [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: MacBottleTheme.gridSpacing)]

    private var recentPrograms: [Program] {
        bottle.programs
            .filter { $0.settings.lastLaunchedAt != nil }
            .sorted { ($0.settings.lastLaunchedAt ?? .distantPast) > ($1.settings.lastLaunchedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    launchStatusBanner

                    BottleHeroHeader(bottle: bottle)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("bottle.section.pinned")
                                .font(.headline)
                            Spacer()
                            Text("bottle.section.pinned.hint")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: gridLayout, alignment: .leading, spacing: MacBottleTheme.gridSpacing) {
                            ForEach(bottle.pinnedPrograms, id: \.id) { pinnedProgram in
                                PinView(
                                    bottle: bottle,
                                    program: pinnedProgram.program,
                                    pin: pinnedProgram.pin,
                                    path: $path,
                                    isSelected: selectedProgramURL == pinnedProgram.program.url,
                                    onSelect: {
                                        selectedProgramURL = pinnedProgram.program.url
                                    }
                                )
                            }
                            PinAddView(bottle: bottle)
                        }
                    }

                    if !recentPrograms.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("bottle.section.recent")
                                    .font(.headline)
                                Spacer()
                                NavigationLink(value: BottleStage.programs) {
                                    Text("bottle.section.recent.all")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            VStack(spacing: 8) {
                                ForEach(recentPrograms, id: \.id) { program in
                                    RecentProgramRow(program: program, path: $path)
                                }
                            }
                        }
                    }

                }
                .padding(MacBottleTheme.pagePadding)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .bottomBar {
                bottleBottomBar
            }
            .onAppear {
                Task { await updateStartMenu() }
                if selectedProgramURL == nil {
                    selectedProgramURL = bottle.pinnedPrograms.first?.program.url
                }
                Task(priority: .utility) {
                    await Wine.ensureBottleReady(bottle)
                }
            }
            .onChange(of: bottle.pinnedPrograms.map(\.program.url)) { _, urls in
                if let selectedProgramURL, urls.contains(selectedProgramURL) {
                    return
                }
                selectedProgramURL = urls.first
            }
            .disabled(!bottle.isAvailable)
            .navigationTitle(bottle.settings.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("bottle.manage.programs.title", systemImage: "list.bullet.rectangle") {
                            path.append(BottleStage.programs)
                        }
                        Button("bottle.manage.config.title", systemImage: "slider.horizontal.3") {
                            path.append(BottleStage.config)
                        }
                        Button("bottle.manage.processes.title", systemImage: "list.bullet.rectangle.portrait") {
                            path.append(BottleStage.processes)
                        }
                        Button("bottle.manage.logs.title", systemImage: "doc.text") {
                            path.append(BottleStage.logs)
                        }
                        Divider()
                        Button("workspace.import.title", systemImage: "tray.and.arrow.down") {
                            showWorkspaceImport.toggle()
                        }
                    } label: {
                        Label("bottle.section.manage", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .sheet(isPresented: $showWorkspaceImport) {
                WorkspaceImportView(bottle: bottle)
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                // Trigger a reload
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(
                        bottle: bottle, path: $path
                    )
                case .processes:
                    RunningProcessesView(bottle: bottle)
                case .logs:
                    ProgramLogsView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

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
                NavigationLink(value: BottleStage.logs) {
                    Text("bottle.launch.viewLogs")
                        .font(.caption.weight(.semibold))
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
                .fill(tint.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: launchCoordinator.phase)
    }

    @ViewBuilder
    private var bottleBottomBar: some View {
        HStack(spacing: 10) {
            Button {
                bottle.openCDrive()
            } label: {
                Label("bottle.bar.cDrive", systemImage: "internaldrive")
            }
            Button {
                bottle.openTerminal()
            } label: {
                Label("bottle.bar.terminal", systemImage: "terminal")
            }
            Button {
                showWinetricksSheet.toggle()
            } label: {
                Label("bottle.menu.winetricks", systemImage: "wrench.and.screwdriver")
            }
            Button(role: .destructive) {
                BottleForceStop.forceStop(bottle: bottle, reason: "bottle-bar")
            } label: {
                Label("bottle.bar.forceStop", systemImage: "xmark.octagon.fill")
            }
            .help("bottle.bar.forceStop.help")
            Spacer()
            if programLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Menu {
                if !bottle.pinnedPrograms.isEmpty {
                    Section("bottle.section.pinned") {
                        ForEach(bottle.pinnedPrograms, id: \.id) { pinned in
                            Button {
                                selectedProgramURL = pinned.program.url
                                pinned.program.run()
                            } label: {
                                Label(pinned.pin.name, systemImage: "play.fill")
                            }
                        }
                    }
                }
                Button("bottle.bar.browsePrograms", systemImage: "folder") {
                    runExternalProgram()
                }
            } label: {
                Label(primaryRunTitle, systemImage: "play.fill")
            } primaryAction: {
                runPrimaryProgram()
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.borderedProminent)
            .disabled(programLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var selectedPinnedProgram: Program? {
        guard let selectedProgramURL else { return nil }
        return bottle.pinnedPrograms.first(where: { $0.program.url == selectedProgramURL })?.program
    }

    private var primaryRunTitle: String {
        if let selected = selectedPinnedProgram {
            return String(format: String(localized: "bottle.bar.runSelected %@"), selectedPinnedName(for: selected))
        }
        if bottle.pinnedPrograms.count == 1, let only = bottle.pinnedPrograms.first {
            return String(format: String(localized: "bottle.bar.runSelected %@"), only.pin.name)
        }
        if let first = bottle.pinnedPrograms.first {
            return String(format: String(localized: "bottle.bar.runSelected %@"), first.pin.name)
        }
        return String(localized: "bottle.bar.runProgram")
    }

    private func selectedPinnedName(for program: Program) -> String {
        bottle.pinnedPrograms.first(where: { $0.program.url == program.url })?.pin.name
            ?? program.name
    }

    private func runPrimaryProgram() {
        if let selected = selectedPinnedProgram {
            selected.run()
            return
        }
        if let first = bottle.pinnedPrograms.first {
            selectedProgramURL = first.program.url
            first.program.run()
            return
        }
        runExternalProgram()
    }

    private func updateStartMenu() async {
        await bottle.refreshInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            // For some godforsaken reason "foo/bar" != "foo/Bar" so...
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                if !bottle.settings.pins.contains(where: { $0.url == program.url }) {
                    bottle.settings.pins.append(PinnedProgram(
                        name: program.url.deletingPathExtension().lastPathComponent,
                        url: program.url
                    ))
                }
            }
        }
    }

    private func runExternalProgram() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "exe") ?? .data,
            UTType(filenameExtension: "msi") ?? .data,
            UTType(filenameExtension: "bat") ?? .data,
            UTType(filenameExtension: "cmd") ?? .data
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
                    Task { @MainActor in
                        programLoading = false
                        await updateStartMenu()
                    }
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
                            environment: ["WINEDLLOVERRIDES": ""],
                            wait: false,
                            applyDXVK: false
                        )
                    }
                    await MainActor.run {
                        let launchedFormat = String(localized: "bottle.run.info.launched.message %@")
                        presentRunInfo(
                            title: String(localized: "bottle.run.info.launched.title"),
                            message: String(format: launchedFormat, selected.lastPathComponent)
                        )
                    }
                } catch {
                    await MainActor.run {
                        presentRunInfo(
                            title: String(localized: "bottle.run.info.failed.title"),
                            message: error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    private func prepareLaunchURL(_ url: URL) throws -> URL {
        let bottlePath = bottle.url.path
        let selectedPath = url.path
        if selectedPath.hasPrefix(bottlePath) {
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

    @MainActor
    private func presentRunInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
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
