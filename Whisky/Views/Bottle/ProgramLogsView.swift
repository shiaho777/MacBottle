//
//  ProgramLogsView.swift
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

struct ProgramLogsView: View {
    @Bindable var bottle: Bottle
    @State private var store = ProgramRunLogStore.shared
    @State private var selectedProgramKey: String?
    @State private var selectedRunID: UUID?
    @State private var selectedRunIDs: Set<UUID> = []
    @State private var sort: ProgramRunLogSort = .newest
    @State private var detailText: String = ""
    @State private var autoScroll = true
    @State private var verboseWineDebug = ProgramRunLogStore.verboseWineDebugEnabled

    private var programs: [ProgramRunProgramSummary] {
        _ = store.revision
        return store.programs(for: bottle, sort: sort)
    }

    private var runs: [ProgramRunRecord] {
        _ = store.revision
        guard let selectedProgramKey else { return [] }
        return store.runs(for: bottle, programKey: selectedProgramKey, sort: sort)
    }

    private var selectedRun: ProgramRunRecord? {
        if let selectedRunID,
           let run = runs.first(where: { $0.id == selectedRunID }) {
            return run
        }
        return runs.first
    }

    var body: some View {
        HSplitView {
            programSidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            runList
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)

            logDetail
                .frame(minWidth: 360)
        }
        .navigationTitle("运行日志")
        .toolbar {
            ToolbarItemGroup {
                Picker("排序", selection: $sort) {
                    ForEach(ProgramRunLogSort.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Toggle("详细调试", isOn: $verboseWineDebug)
                    .toggleStyle(.checkbox)
                    .help("开启后日志更详细，但启动会明显变慢")
                    .onChange(of: verboseWineDebug) { _, newValue in
                        ProgramRunLogStore.verboseWineDebugEnabled = newValue
                    }

                Button("导出", systemImage: "square.and.arrow.down") {
                    exportSelected()
                }
                .disabled(selectedRun == nil)

                Button("复制", systemImage: "doc.on.doc") {
                    copySelected()
                }
                .disabled(detailText.isEmpty)

                Button("删除", systemImage: "trash") {
                    deleteSelected()
                }
                .disabled(selectedRunIDs.isEmpty && selectedRun == nil)

                Menu("清理", systemImage: "trash.slash") {
                    Button("清空当前程序日志", role: .destructive) {
                        if let selectedProgramKey {
                            store.clearProgram(bottle: bottle, programKey: selectedProgramKey)
                            self.selectedRunID = nil
                            selectedRunIDs = []
                            detailText = ""
                        }
                    }
                    .disabled(selectedProgramKey == nil)

                    Button("清空本容器全部日志", role: .destructive) {
                        store.clearBottle(bottle)
                        selectedProgramKey = nil
                        selectedRunID = nil
                        selectedRunIDs = []
                        detailText = ""
                    }
                }
            }
        }
        .onAppear {
            focusLatestActivity()
            refreshDetail()
        }
        .onChange(of: store.revision) { _, _ in
            if selectedProgramKey == nil || !programs.contains(where: { $0.programKey == selectedProgramKey }) {
                focusLatestActivity()
            }
            refreshDetail()
        }
        .onChange(of: selectedProgramKey) { _, _ in
            selectedRunID = runs.first?.id
            selectedRunIDs = []
            refreshDetail()
        }
        .onChange(of: selectedRunID) { _, _ in
            refreshDetail()
        }
        .onChange(of: sort) { _, _ in
            refreshDetail()
        }
    }

    private var programSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("程序")
                .font(.headline)
                .padding(12)
            Divider()
            if programs.isEmpty {
                emptyState(
                    title: "暂无程序日志",
                    subtitle: "运行程序后会按程序分类记录完整日志"
                )
            } else {
                List(programs, selection: $selectedProgramKey) { program in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.programName)
                                .lineLimit(1)
                            Text("\(program.runCount) 次运行")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if program.hasRunning {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .tag(program.programKey)
                    .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var runList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("运行记录")
                    .font(.headline)
                Spacer()
                if !selectedRunIDs.isEmpty {
                    Text("已选 \(selectedRunIDs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            if runs.isEmpty {
                emptyState(title: "无运行记录", subtitle: "选择左侧程序查看每次运行日志")
            } else {
                List(selection: $selectedRunIDs) {
                    ForEach(runs) { run in
                        runRow(run)
                            .tag(run.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRunID = run.id
                                selectedRunIDs = [run.id]
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func runRow(_ run: ProgramRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(run.startedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.body.weight(.medium))
                Spacer()
                Text(run.statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(run.status))
            }
            HStack {
                Text(durationText(run))
                if let code = run.exitCode {
                    Text("退出码 \(code)")
                }
                if run.byteCount > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(run.byteCount), countStyle: .file))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var logDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let run = selectedRun {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.programName)
                            .font(.headline)
                        Text(run.startedAt.formatted(date: .complete, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if run.status == .running {
                        Label("实时输出", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("日志内容")
                        .font(.headline)
                }
                Spacer()
                Toggle("跟随底部", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button("在 Finder 中显示") {
                    revealSelected()
                }
                .disabled(selectedRun == nil)
            }
            .padding(12)
            Divider()

            if detailText.isEmpty {
                emptyState(title: "选择一条运行记录", subtitle: "可查看、复制、导出完整日志")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(detailText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .id("log-bottom")
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: detailText) { _, _ in
                        guard autoScroll else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("log-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func focusLatestActivity() {
        let programList = programs
        if let running = programList.first(where: { $0.hasRunning }) {
            selectedProgramKey = running.programKey
        } else if selectedProgramKey == nil {
            selectedProgramKey = programList.first?.programKey
        }

        let runList = runs
        if let running = runList.first(where: { $0.status == .running }) {
            selectedRunID = running.id
            selectedRunIDs = [running.id]
        } else if selectedRunID == nil {
            selectedRunID = runList.first?.id
        }
    }

    private func refreshDetail() {
        guard let run = selectedRun else {
            detailText = ""
            return
        }
        if selectedRunID != run.id {
            selectedRunID = run.id
        }
        let session = store.loadSessionText(for: run)
        detailText = session.text
    }

    private func copySelected() {
        guard !detailText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(detailText, forType: .string)
    }

    private func exportSelected() {
        guard let run = selectedRun else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(run.programName)-\(run.id.uuidString.prefix(8)).log"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try store.exportRun(run, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "导出失败"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func deleteSelected() {
        var targets: [ProgramRunRecord] = []
        if !selectedRunIDs.isEmpty {
            targets = runs.filter { selectedRunIDs.contains($0.id) }
        } else if let selectedRun {
            targets = [selectedRun]
        }
        guard !targets.isEmpty else { return }
        store.deleteRuns(targets)
        selectedRunIDs = []
        selectedRunID = runs.first?.id
        refreshDetail()
    }

    private func revealSelected() {
        guard let run = selectedRun else { return }
        let url = store.logFileURL(for: run)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func statusColor(_ status: ProgramRunStatus) -> Color {
        switch status {
        case .running: return .green
        case .finished: return .secondary
        case .failed: return .red
        }
    }

    private func durationText(_ run: ProgramRunRecord) -> String {
        let seconds = Int(run.duration.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
