//
//  ProgramsView.swift
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
import WhiskyKit

private enum ProgramsPane: String, CaseIterable, Identifiable {
    case library
    case recent
    case blocklist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "程序库"
        case .recent: return "最近运行"
        case .blocklist: return "屏蔽列表"
        }
    }
}

private enum ProgramFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case unpinned
    case x64
    case x86
    case games
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .pinned: return "已固定"
        case .unpinned: return "未固定"
        case .x64: return "64 位"
        case .x86: return "32 位"
        case .games: return "游戏/主程序"
        case .tools: return "工具/安装器"
        }
    }
}

private enum ProgramSort: String, CaseIterable, Identifiable {
    case pinnedFirst
    case recent
    case name
    case folder
    case architecture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pinnedFirst: return "固定优先"
        case .recent: return "最近运行"
        case .name: return "名称"
        case .folder: return "目录"
        case .architecture: return "架构"
        }
    }
}

private enum ProgramLayout: String, CaseIterable, Identifiable {
    case flat
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: return "列表"
        case .folders: return "按文件夹"
        }
    }

    var systemImage: String {
        switch self {
        case .flat: return "list.bullet"
        case .folders: return "folder"
        }
    }
}

private struct ProgramFolderGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let programs: [Program]
}

struct ProgramsView: View {
    @Bindable var bottle: Bottle
    @Binding var path: NavigationPath

    @State private var pane: ProgramsPane = .library
    @State private var filter: ProgramFilter = .all
    @State private var sort: ProgramSort = .pinnedFirst
    @State private var layout: ProgramLayout = .flat
    @State private var searchText = ""
    @State private var programs: [Program] = []
    @State private var blocklist: [URL] = []
    @State private var selectedPrograms = Set<Program.ID>()
    @State private var selectedBlockitems = Set<URL>()
    @State private var isRefreshing = false
    @State private var hideSystemNoise = true
    @State private var expandedFolders: Set<String> = []

    private var filteredPrograms: [Program] {
        var items = programs

        if hideSystemNoise {
            items = items.filter { !Self.isSystemNoise($0) }
        }

        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.url.path(percentEncoded: false).localizedCaseInsensitiveContains(searchText)
            }
        }

        switch filter {
        case .all: break
        case .pinned: items = items.filter(\.pinned)
        case .unpinned: items = items.filter { !$0.pinned }
        case .x64: items = items.filter { $0.peFile?.architecture == .x64 }
        case .x86: items = items.filter { $0.peFile?.architecture == .x32 }
        case .games: items = items.filter { !Self.isInstallerOrTool($0) }
        case .tools: items = items.filter { Self.isInstallerOrTool($0) }
        }

        return sortPrograms(items)
    }

    private var recentPrograms: [Program] {
        var items = programs.filter { $0.settings.lastLaunchedAt != nil }
        if hideSystemNoise {
            items = items.filter { !Self.isSystemNoise($0) }
        }
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.url.path(percentEncoded: false).localizedCaseInsensitiveContains(searchText)
            }
        }
        return items.sorted {
            ($0.settings.lastLaunchedAt ?? .distantPast) > ($1.settings.lastLaunchedAt ?? .distantPast)
        }
    }

    private var folderGroups: [ProgramFolderGroup] {
        let grouped = Dictionary(grouping: filteredPrograms) { program in
            program.url.deletingLastPathComponent()
        }
        return grouped.keys.sorted {
            $0.path(percentEncoded: false).localizedCaseInsensitiveCompare($1.path(percentEncoded: false))
                == .orderedAscending
        }.compactMap { folderURL in
            guard let items = grouped[folderURL] else { return nil }
            let sortedItems = sortPrograms(items)
            return ProgramFolderGroup(
                id: folderURL.path(percentEncoded: false),
                title: folderURL.lastPathComponent,
                subtitle: folderURL.prettyPath(bottle),
                programs: sortedItems
            )
        }
    }

    private var selectedProgramObjects: [Program] {
        let pool = pane == .recent ? recentPrograms : filteredPrograms
        return pool.filter { selectedPrograms.contains($0.id) }
    }

    private var statsLine: String {
        switch pane {
        case .library:
            return "共 \(programs.count) 个 · 固定 \(programs.filter(\.pinned).count) · 显示 \(filteredPrograms.count)"
        case .recent:
            return "最近运行 \(recentPrograms.count) 个"
        case .blocklist:
            return "已屏蔽 \(blocklist.count) 个"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch pane {
            case .library:
                libraryContent
            case .recent:
                recentContent
            case .blocklist:
                blocklistContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("已安装程序")
        .searchable(text: $searchText, prompt: "搜索名称或路径")
        .toolbar { toolbarContent }
        .onAppear {
            reload(rescan: false)
            if expandedFolders.isEmpty {
                expandedFolders = Set(folderGroups.prefix(8).map(\.id))
            }
        }
        .onChange(of: bottle.settings.pins) { _, _ in
            reload(rescan: false)
        }
        .onChange(of: bottle.settings.blocklist) { _, _ in
            blocklist = bottle.settings.blocklist
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("面板", selection: $pane) {
                    ForEach(ProgramsPane.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                Text(statsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if pane == .library {
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ProgramFilter.allCases) { item in
                                FilterChip(title: item.title, isSelected: filter == item) {
                                    filter = item
                                }
                            }
                        }
                    }

                    Picker("布局", selection: $layout) {
                        ForEach(ProgramLayout.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    Picker("排序", selection: $sort) {
                        ForEach(ProgramSort.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    Toggle("隐藏系统噪声", isOn: $hideSystemNoise)
                        .toggleStyle(.checkbox)
                        .help("隐藏 uninstall、crash、redist 等常见非主程序")
                }
            } else if pane == .recent {
                Toggle("隐藏系统噪声", isOn: $hideSystemNoise)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var libraryContent: some View {
        if filteredPrograms.isEmpty {
            EmptyStateCard(
                systemImage: searchText.isEmpty ? "shippingbox" : "magnifyingglass",
                title: searchText.isEmpty ? "还没有可显示的程序" : "没有匹配结果",
                message: searchText.isEmpty
                    ? "点右上角刷新扫描 drive_c。也可从固定区或底部「浏览其他程序」导入。"
                    : "试试换关键词，或关闭「隐藏系统噪声」。",
                actionTitle: searchText.isEmpty ? "刷新扫描" : nil,
                action: searchText.isEmpty ? { refreshPrograms() } : nil
            )
        } else if layout == .folders {
            folderLibraryList
        } else {
            flatLibraryList(filteredPrograms)
        }
    }

    @ViewBuilder
    private var recentContent: some View {
        if recentPrograms.isEmpty {
            EmptyStateCard(
                systemImage: "clock.arrow.circlepath",
                title: "还没有运行记录",
                message: "从程序库或固定区启动程序后，会按时间显示在这里，方便一键再开。"
            )
        } else {
            flatLibraryList(recentPrograms, showRecentTime: true)
        }
    }

    private func flatLibraryList(_ items: [Program], showRecentTime: Bool = false) -> some View {
        List(selection: $selectedPrograms) {
            ForEach(items, id: \.id) { program in
                ProgramLibraryRow(
                    program: program,
                    bottle: bottle,
                    showRecentTime: showRecentTime || sort == .recent
                )
                .tag(program.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    program.run()
                    reload(rescan: false)
                }
                .contextMenu {
                    programContextMenu(for: program)
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
    }

    private var folderLibraryList: some View {
        List(selection: $selectedPrograms) {
            ForEach(folderGroups) { group in
                Section {
                    if expandedFolders.contains(group.id) {
                        ForEach(group.programs, id: \.id) { program in
                            ProgramLibraryRow(
                                program: program,
                                bottle: bottle,
                                showRecentTime: sort == .recent
                            )
                            .tag(program.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                program.run()
                                reload(rescan: false)
                            }
                            .contextMenu {
                                programContextMenu(for: program)
                            }
                        }
                    }
                } header: {
                    Button {
                        if expandedFolders.contains(group.id) {
                            expandedFolders.remove(group.id)
                        } else {
                            expandedFolders.insert(group.id)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: expandedFolders.contains(group.id) ? "folder.fill" : "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(group.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text("\(group.programs.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: expandedFolders.contains(group.id) ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
    }

    @ViewBuilder
    private var blocklistContent: some View {
        if blocklist.isEmpty {
            EmptyStateCard(
                systemImage: "hand.raised",
                title: "屏蔽列表为空",
                message: "被屏蔽的 exe 不会再出现在程序库扫描结果中。可从程序库右键加入。"
            )
        } else {
            List(selection: $selectedBlockitems) {
                ForEach(filteredBlocklist, id: \.self) { url in
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.body.weight(.medium))
                            Text(url.prettyPath(bottle))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("移除") {
                            removeFromBlocklist([url])
                        }
                        .buttonStyle(.borderless)
                    }
                    .tag(url)
                    .contextMenu {
                        Button("移除屏蔽", systemImage: "hand.raised.slash") {
                            removeFromBlocklist(
                                selectedBlockitems.isEmpty ? [url] : Array(selectedBlockitems)
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
        }
    }

    private var filteredBlocklist: [URL] {
        let items: [URL]
        if searchText.isEmpty {
            items = blocklist
        } else {
            items = blocklist.filter {
                $0.lastPathComponent.localizedCaseInsensitiveContains(searchText)
                    || $0.path(percentEncoded: false).localizedCaseInsensitiveContains(searchText)
            }
        }
        return items.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if pane != .blocklist {
                Button {
                    runSelectedOrFirst()
                } label: {
                    Label("运行", systemImage: "play.fill")
                }
                .disabled(selectedProgramObjects.isEmpty && currentList.isEmpty)

                Button {
                    togglePinSelected()
                } label: {
                    Label("固定", systemImage: "pin")
                }
                .disabled(selectedProgramObjects.isEmpty)

                Button {
                    openConfigSelected()
                } label: {
                    Label("配置", systemImage: "gearshape")
                }
                .disabled(selectedProgramObjects.count != 1)

                Button {
                    blockSelected()
                } label: {
                    Label("屏蔽", systemImage: "hand.raised")
                }
                .disabled(selectedProgramObjects.isEmpty)

                Button {
                    revealSelected()
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
                .disabled(selectedProgramObjects.isEmpty)

                if pane == .recent {
                    Button {
                        clearRecentSelected()
                    } label: {
                        Label("清除记录", systemImage: "clock.badge.xmark")
                    }
                    .disabled(selectedProgramObjects.isEmpty && recentPrograms.isEmpty)
                    .help("清除选中项的最近运行时间；未选中则清空全部")
                }
            } else {
                Button {
                    removeFromBlocklist(Array(selectedBlockitems))
                } label: {
                    Label("移除屏蔽", systemImage: "hand.raised.slash")
                }
                .disabled(selectedBlockitems.isEmpty)
            }

            if pane == .library, layout == .folders {
                Button {
                    expandedFolders = Set(folderGroups.map(\.id))
                } label: {
                    Label("全部展开", systemImage: "rectangle.expand.vertical")
                }
                Button {
                    expandedFolders.removeAll()
                } label: {
                    Label("全部折叠", systemImage: "rectangle.compress.vertical")
                }
            }

            Button {
                refreshPrograms()
            } label: {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)
        }
    }

    private var currentList: [Program] {
        switch pane {
        case .library: return filteredPrograms
        case .recent: return recentPrograms
        case .blocklist: return []
        }
    }

    @ViewBuilder
    private func programContextMenu(for program: Program) -> some View {
        let targets = selectedProgramObjects.contains(program) && selectedProgramObjects.count > 1
            ? selectedProgramObjects
            : [program]

        Button("运行", systemImage: "play.fill") {
            targets.forEach { $0.run() }
            reload(rescan: false)
        }
        Button(program.pinned ? "取消固定" : "固定到主页", systemImage: "pin") {
            targets.forEach { $0.pinned.toggle() }
            reload(rescan: false)
        }
        Button("程序配置", systemImage: "gearshape") {
            path.append(program)
        }
        .disabled(targets.count != 1)
        Divider()
        Button("在 Finder 中显示", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
        }
        Button("加入屏蔽列表", systemImage: "hand.raised") {
            addToBlocklist(targets.map(\.url))
        }
        if targets.contains(where: { $0.settings.lastLaunchedAt != nil }) {
            Button("清除运行记录", systemImage: "clock.badge.xmark") {
                targets.forEach {
                    $0.settings.lastLaunchedAt = nil
                }
                reload(rescan: false)
            }
        }
    }

    private func sortPrograms(_ items: [Program]) -> [Program] {
        var items = items
        switch sort {
        case .pinnedFirst:
            items.sort {
                if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recent:
            items.sort {
                ($0.settings.lastLaunchedAt ?? .distantPast) > ($1.settings.lastLaunchedAt ?? .distantPast)
            }
        case .name:
            items.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .folder:
            items.sort {
                let left = $0.url.deletingLastPathComponent().path(percentEncoded: false)
                let right = $1.url.deletingLastPathComponent().path(percentEncoded: false)
                if left != right {
                    return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .architecture:
            items.sort {
                let left = $0.peFile?.architecture.toString() ?? "zzz"
                let right = $1.peFile?.architecture.toString() ?? "zzz"
                if left != right { return left < right }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return items
    }

    private func reload(rescan: Bool) {
        if rescan {
            bottle.updateInstalledPrograms()
        }
        programs = bottle.programs.filter {
            FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false))
        }
        blocklist = bottle.settings.blocklist.filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
        selectedPrograms = selectedPrograms.intersection(Set(programs.map(\.id)))
    }

    private func refreshPrograms() {
        isRefreshing = true
        Task { @MainActor in
            bottle.updateInstalledPrograms()
            reload(rescan: false)
            isRefreshing = false
        }
    }

    private func runSelectedOrFirst() {
        if !selectedProgramObjects.isEmpty {
            selectedProgramObjects.forEach { $0.run() }
        } else {
            currentList.first?.run()
        }
        reload(rescan: false)
    }

    private func togglePinSelected() {
        selectedProgramObjects.forEach { $0.pinned.toggle() }
        reload(rescan: false)
    }

    private func openConfigSelected() {
        guard let program = selectedProgramObjects.first, selectedProgramObjects.count == 1 else { return }
        path.append(program)
    }

    private func blockSelected() {
        addToBlocklist(selectedProgramObjects.map(\.url))
    }

    private func revealSelected() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedProgramObjects.map(\.url))
    }

    private func clearRecentSelected() {
        let targets = selectedProgramObjects.isEmpty ? recentPrograms : selectedProgramObjects
        targets.forEach { $0.settings.lastLaunchedAt = nil }
        reload(rescan: false)
    }

    private func addToBlocklist(_ urls: [URL]) {
        var list = bottle.settings.blocklist
        for url in urls where !list.contains(url) {
            list.append(url)
        }
        bottle.settings.blocklist = list
        blocklist = list
        selectedPrograms.removeAll()
        reload(rescan: true)
    }

    private func removeFromBlocklist(_ urls: [URL]) {
        bottle.settings.blocklist.removeAll { urls.contains($0) }
        blocklist = bottle.settings.blocklist
        selectedBlockitems.removeAll()
        reload(rescan: true)
    }

    private static func isInstallerOrTool(_ program: Program) -> Bool {
        let name = program.name.lowercased()
        let markers = [
            "setup", "install", "uninstall", "unins", "update", "patch",
            "redist", "vcredist", "directx", "dotnet", "launcher_uninstall",
            "crash", "report", "helper", "service"
        ]
        return markers.contains { name.contains($0) }
    }

    private static func isSystemNoise(_ program: Program) -> Bool {
        let path = program.url.path(percentEncoded: false).lowercased()
        let name = program.name.lowercased()
        if path.contains("/windows/") { return true }
        if path.contains("/common files/") && (name.contains("update") || name.contains("install")) {
            return true
        }
        let noiseNames = [
            "unins000.exe", "uninstall.exe", "unitycrashhandler", "crashpad",
            "vc_redist", "vcredist", "dxsetup.exe", "dotnetfx", "installagent"
        ]
        return noiseNames.contains { name.contains($0) || path.contains($0) }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    Capsule().strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct ProgramLibraryRow: View {
    @Bindable var program: Program
    @Bindable var bottle: Bottle
    var showRecentTime: Bool = false

    @State private var icon: Image?

    private var relativePath: String {
        program.url.prettyPath(bottle)
    }

    private var folderName: String {
        program.url.deletingLastPathComponent().lastPathComponent
    }

    private var recentText: String? {
        guard let date = program.settings.lastLaunchedAt else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                if let icon {
                    icon
                        .resizable()
                        .interpolation(.high)
                        .padding(6)
                } else {
                    Image(systemName: "app.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(program.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if program.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if showRecentTime, let recentText {
                StatusPill(title: recentText, systemImage: "clock", color: .teal)
            }

            if let arch = program.peFile?.architecture.toString() {
                StatusPill(title: arch, color: arch.contains("64") ? .blue : .purple)
            }

            StatusPill(title: folderName, systemImage: "folder", color: .secondary)

            Button {
                program.pinned.toggle()
            } label: {
                Image(systemName: program.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(program.pinned ? "取消固定" : "固定")

            Button {
                program.run()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("运行")
        }
        .padding(.vertical, 4)
        .task(id: program.url) {
            guard let peFile = program.peFile else {
                icon = nil
                return
            }
            icon = await Task.detached {
                guard let nsImage = peFile.bestIcon() else { return nil as Image? }
                return Image(nsImage: nsImage)
            }.value
        }
    }
}
