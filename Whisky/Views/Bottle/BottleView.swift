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
    @State private var path = NavigationPath()
    @State private var programLoading: Bool = false
    @State private var showWinetricksSheet: Bool = false
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
                    BottleHeroHeader(bottle: bottle)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("固定程序")
                                .font(.headline)
                            Spacer()
                            Text("点击启动 · 拖拽排序")
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
                                Text("最近运行")
                                    .font(.headline)
                                Spacer()
                                NavigationLink(value: BottleStage.programs) {
                                    Text("全部")
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("管理")
                            .font(.headline)
                        NavigationLink(value: BottleStage.programs) {
                            QuickActionTile(
                                title: "已安装程序",
                                systemImage: "list.bullet.rectangle",
                                subtitle: "筛选、分组、最近运行与屏蔽管理"
                            )
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: BottleStage.config) {
                            QuickActionTile(
                                title: "容器配置",
                                systemImage: "slider.horizontal.3",
                                subtitle: "Windows 版本、引擎绑定、DXVK、Metal"
                            )
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: BottleStage.processes) {
                            QuickActionTile(
                                title: "运行中的进程",
                                systemImage: "list.bullet.rectangle.portrait",
                                subtitle: "查看并结束容器内 Windows 进程"
                            )
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: BottleStage.logs) {
                            QuickActionTile(
                                title: "运行日志",
                                systemImage: "doc.text",
                                subtitle: "按程序查看完整运行日志与实时输出"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(MacBottleTheme.pagePadding)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .bottomBar {
                bottleBottomBar
            }
            .onAppear {
                updateStartMenu()
                if selectedProgramURL == nil {
                    selectedProgramURL = bottle.pinnedPrograms.first?.program.url
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
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
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


    @ViewBuilder
    private var bottleBottomBar: some View {
        HStack(spacing: 10) {
            Button {
                bottle.openCDrive()
            } label: {
                Label("C 盘", systemImage: "internaldrive")
            }
            Button {
                bottle.openTerminal()
            } label: {
                Label("终端", systemImage: "terminal")
            }
            Button {
                showWinetricksSheet.toggle()
            } label: {
                Label("Winetricks", systemImage: "wrench.and.screwdriver")
            }
            Button {
                path.append(BottleStage.logs)
            } label: {
                Label("运行日志", systemImage: "doc.text")
            }
            Spacer()
            if programLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Menu {
                if !bottle.pinnedPrograms.isEmpty {
                    Section("固定程序") {
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
                Button("浏览其他程序…", systemImage: "folder") {
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
            return "运行 \(selectedPinnedName(for: selected))"
        }
        if bottle.pinnedPrograms.count == 1, let only = bottle.pinnedPrograms.first {
            return "运行 \(only.pin.name)"
        }
        if let first = bottle.pinnedPrograms.first {
            return "运行 \(first.pin.name)"
        }
        return "运行程序"
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

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            // For some godforsaken reason "foo/bar" != "foo/Bar" so...
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !bottle.settings.pins.contains(where: { $0.url == program.url }) else { return }
                bottle.settings.pins.append(PinnedProgram(
                    name: program.url.deletingPathExtension().lastPathComponent,
                    url: program.url
                ))
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
        panel.message = "选择要在此容器中运行的 Windows 程序（.exe / .msi）"
        panel.prompt = "运行"

        panel.begin { result in
            guard result == .OK, let selected = panel.url else { return }
            programLoading = true
            Task(priority: .userInitiated) {
                defer {
                    Task { @MainActor in
                        programLoading = false
                        updateStartMenu()
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
                        presentRunInfo(
                            title: "已启动",
                            message: "正在运行：\(selected.lastPathComponent)\n\n若没有窗口出现，请换一个新建的空容器再试（不要用已开 DXVK 的游戏容器跑安装包）。"
                        )
                    }
                } catch {
                    await MainActor.run {
                        presentRunInfo(
                            title: "启动失败",
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
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}


private struct RecentProgramRow: View {
    @Bindable var program: Program
    @Binding var path: NavigationPath

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
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
            Button("配置") {
                path.append(program)
            }
            .buttonStyle(.borderless)
            Button {
                program.run()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("运行")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                .fill(.background.secondary)
        }
    }
}


