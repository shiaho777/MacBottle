//
//  ProgramView.swift
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
import UniformTypeIdentifiers

struct ProgramView: View {
    @Bindable var program: Program
    @State private var programLoading = false
    @State private var cachedIconImage: Image?
    @State private var showProgramLogs = false
    @AppStorage("configSectionExapnded") private var configSectionExpanded = true
    @AppStorage("envArgsSectionExpanded") private var envArgsSectionExpanded = true
    @AppStorage("recipeSectionExpanded") private var recipeSectionExpanded = true

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                programHeader

                Form {
                    Section("program.config", isExpanded: $configSectionExpanded) {
                        Picker("locale.title", selection: $program.settings.locale) {
                            ForEach(Locales.allCases, id: \.self) { locale in
                                Text(locale.pretty()).id(locale)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("program.args")
                            TextField("program.args", text: $program.settings.arguments)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .labelsHidden()
                        }
                    }
                    RecipeSection(program: program, isExpanded: $recipeSectionExpanded)
                    EnvironmentArgView(program: program, isExpanded: $envArgsSectionExpanded)
                }
                .formStyle(.grouped)
            }
            .padding(MacBottleTheme.pagePadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .bottomBar {
            HStack(spacing: 10) {
                Button {
                    program.pinned.toggle()
                } label: {
                    Label(
                        program.pinned ? "取消固定" : "固定到主页",
                        systemImage: program.pinned ? "pin.slash" : "pin"
                    )
                }
                Button("button.showInFinder") {
                    NSWorkspace.shared.activateFileViewerSelecting([program.url])
                }
                Button("button.createShortcut") {
                    createShortcut()
                }
                Button("运行日志") {
                    showProgramLogs = true
                }
                Spacer()
                if programLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    programLoading = true
                    program.run()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1200))
                        programLoading = false
                    }
                } label: {
                    Label("运行", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(programLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showProgramLogs) {
            NavigationStack {
                ProgramLogsView(bottle: program.bottle)
            }
            .frame(minWidth: 900, minHeight: 560)
        }
        .navigationTitle(program.name)
        .animation(.whiskyDefault, value: configSectionExpanded)
        .animation(.whiskyDefault, value: envArgsSectionExpanded)
        .animation(.whiskyDefault, value: recipeSectionExpanded)
        .task {
            if let fetchedImage = program.peFile?.bestIcon() {
                cachedIconImage = Image(nsImage: fetchedImage)
            }
        }
    }

    private var programHeader: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                    if let cachedIconImage {
                        cachedIconImage
                            .resizable()
                            .interpolation(.high)
                            .padding(10)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 8) {
                    Text(program.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(program.url.prettyPath(program.bottle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        if let arch = program.peFile?.architecture.toString() {
                            StatusPill(
                                title: arch,
                                systemImage: "cpu",
                                color: arch.contains("64") ? .blue : .purple
                            )
                        }
                        if program.pinned {
                            StatusPill(title: "已固定", systemImage: "pin.fill", color: .orange)
                        }
                        if let last = program.settings.lastLaunchedAt {
                            StatusPill(
                                title: Self.relativeFormatter.localizedString(for: last, relativeTo: Date()),
                                systemImage: "clock",
                                color: .teal
                            )
                        }
                        if program.settings.recipeID != nil {
                            StatusPill(title: "Recipe", systemImage: "list.bullet.rectangle", color: .indigo)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func createShortcut() {
        let panel = NSSavePanel()
        let applicationDir = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)[0]
        let name = program.name.replacingOccurrences(of: ".exe", with: "")
        panel.directoryURL = applicationDir
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = true
        panel.nameFieldStringValue = name + ".app"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                let name = url.deletingPathExtension().lastPathComponent
                Task(priority: .userInitiated) {
                    await ProgramShortcut.createShortcut(program, app: url, name: name)
                }
            }
        }
    }
}
