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
    @State private var isLoadingDetail = false
    @State private var detailToken = UUID()
    @State private var autoScroll = true
    @State private var verboseWineDebug = ProgramRunLogStore.verboseWineDebugEnabled
    @State private var programsCache: [ProgramRunProgramSummary] = []
    @State private var runsCache: [ProgramRunRecord] = []

    private var selectedRun: ProgramRunRecord? {
        if let selectedRunID,
           let run = runsCache.first(where: { $0.id == selectedRunID }) {
            return run
        }
        return runsCache.first
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
        .navigationTitle("logs.title")
        .toolbar {
            ToolbarItemGroup {
                Picker("logs.sort", selection: $sort) {
                    ForEach(ProgramRunLogSort.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Toggle("logs.verbose", isOn: $verboseWineDebug)
                    .toggleStyle(.checkbox)
                    .help("logs.verbose.help")
                    .onChange(of: verboseWineDebug) { _, newValue in
                        ProgramRunLogStore.verboseWineDebugEnabled = newValue
                    }

                Button("logs.export", systemImage: "square.and.arrow.down") {
                    exportSelected()
                }
                .disabled(selectedRun == nil)

                Button("logs.copy", systemImage: "doc.on.doc") {
                    copySelected()
                }
                .disabled(detailText.isEmpty)

                Button("logs.delete", systemImage: "trash") {
                    deleteSelected()
                }
                .disabled(selectedRunIDs.isEmpty && selectedRun == nil)

                Menu("logs.clean", systemImage: "trash.slash") {
                    Button("logs.clean.program", role: .destructive) {
                        if let selectedProgramKey {
                            store.clearProgram(bottle: bottle, programKey: selectedProgramKey)
                            self.selectedRunID = nil
                            selectedRunIDs = []
                            detailText = ""
                            reloadCaches()
                        }
                    }
                    .disabled(selectedProgramKey == nil)

                    Button("logs.clean.bottle", role: .destructive) {
                        store.clearBottle(bottle)
                        selectedProgramKey = nil
                        selectedRunID = nil
                        selectedRunIDs = []
                        detailText = ""
                        reloadCaches()
                    }
                }
            }
        }
        .onAppear {
            store.reconcileStaleRunningRuns(for: bottle)
            reloadCaches()
            focusLatestActivity()
            refreshDetail()
        }
        .task(id: bottle.url) {
            var lastSeenRevision = store.revision
            let bottleKey = ProgramRunLogStore.bottleKey(for: bottle)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                // Idle ticks must not touch disk: skip when nothing is
                // running and no other component bumped the store.
                let hasLiveSession = store.sessions.values.contains {
                    $0.record.bottleKey == bottleKey && $0.isLive
                }
                if !hasLiveSession, store.revision == lastSeenRevision {
                    continue
                }
                lastSeenRevision = store.revision
                store.reconcileStaleRunningRuns(for: bottle)
                reloadCaches()
                if selectedRun?.status == .running {
                    refreshDetail()
                }
            }
        }
        .onChange(of: store.revision) { _, _ in
            reloadCaches()
            if selectedProgramKey == nil || !programsCache.contains(where: { $0.programKey == selectedProgramKey }) {
                focusLatestActivity()
            }
            refreshDetail()
        }
        .onChange(of: selectedProgramKey) { _, _ in
            reloadRunsOnly()
            selectedRunID = runsCache.first?.id
            selectedRunIDs = selectedRunID.map { [$0] } ?? []
            refreshDetail()
        }
        .onChange(of: selectedRunID) { _, _ in
            refreshDetail()
        }
        .onChange(of: sort) { _, _ in
            reloadCaches()
            refreshDetail()
        }
    }

    private var programSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("logs.sidebar.programs")
                .font(.headline)
                .padding(12)
            Divider()
            if programsCache.isEmpty {
                emptyState(
                    title: "logs.empty.programs.title",
                    subtitle: "logs.empty.programs.subtitle"
                )
            } else {
                List(programsCache, selection: $selectedProgramKey) { program in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.programName)
                                .lineLimit(1)
                            Text("programs.runCount \(program.runCount)")
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
                Text("logs.section.runs")
                    .font(.headline)
                Spacer()
                if !selectedRunIDs.isEmpty {
                    Text("programs.selected \(selectedRunIDs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            if runsCache.isEmpty {
                emptyState(title: "logs.empty.runs.title", subtitle: "logs.empty.runs.subtitle")
            } else {
                List(selection: $selectedRunIDs) {
                    ForEach(runsCache) { run in
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
                    Text("programs.exitCode \(code)")
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
                        Label("logs.liveOutput", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("logs.detail.placeholder")
                        .font(.headline)
                }
                Spacer()
                if isLoadingDetail {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle("logs.followTail", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                if selectedRun?.status == .running {
                    Button("logs.forceStop", role: .destructive) {
                        BottleForceStop.forceStop(bottle: bottle, reason: "run-log")
                        store.reconcileStaleRunningRuns(for: bottle)
                        reloadCaches()
                        refreshDetail()
                    }
                }
                Button("programs.showInFinder") {
                    revealSelected()
                }
                .disabled(selectedRun == nil)
            }
            .padding(12)
            Divider()

            if selectedRun == nil {
                emptyState(title: "logs.empty.detail.title", subtitle: "logs.empty.detail.subtitle")
            } else if isLoadingDetail && detailText.isEmpty {
                emptyState(title: "logs.loading.title", subtitle: "logs.loading.subtitle")
            } else if detailText.isEmpty {
                emptyState(title: "logs.empty.output.title", subtitle: "logs.empty.output.subtitle")
            } else {
                LogTextView(text: detailText, autoScroll: autoScroll)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func emptyState(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
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

    private func reloadCaches() {
        programsCache = store.programs(for: bottle, sort: sort)
        reloadRunsOnly()
    }

    private func reloadRunsOnly() {
        guard let selectedProgramKey else {
            runsCache = []
            return
        }
        runsCache = store.runs(for: bottle, programKey: selectedProgramKey, sort: sort)
    }

    private func focusLatestActivity() {
        if let running = programsCache.first(where: { $0.hasRunning }) {
            selectedProgramKey = running.programKey
        } else if selectedProgramKey == nil {
            selectedProgramKey = programsCache.first?.programKey
        }
        reloadRunsOnly()
        if let running = runsCache.first(where: { $0.status == .running }) {
            selectedRunID = running.id
            selectedRunIDs = [running.id]
        } else if selectedRunID == nil {
            selectedRunID = runsCache.first?.id
            selectedRunIDs = selectedRunID.map { [$0] } ?? []
        }
    }

    private func refreshDetail() {
        guard let run = selectedRun else {
            detailText = ""
            isLoadingDetail = false
            return
        }
        if selectedRunID != run.id {
            selectedRunID = run.id
        }
        let url = store.logFileURL(for: run)
        let runID = run.id
        let token = UUID()
        detailToken = token
        isLoadingDetail = true

        Task.detached(priority: .utility) {
            let text = ProgramRunLogStore.readPreviewText(
                url: url,
                maxBytes: ProgramRunLogStore.previewMaxBytes
            )
            await MainActor.run {
                guard detailToken == token, selectedRunID == runID else { return }
                detailText = text
                isLoadingDetail = false
            }
        }
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
                alert.messageText = String(localized: "logs.export.failed")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func deleteSelected() {
        var targets: [ProgramRunRecord] = []
        if !selectedRunIDs.isEmpty {
            targets = runsCache.filter { selectedRunIDs.contains($0.id) }
        } else if let selectedRun {
            targets = [selectedRun]
        }
        guard !targets.isEmpty else { return }
        store.deleteRuns(targets)
        selectedRunIDs = []
        reloadCaches()
        selectedRunID = runsCache.first?.id
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
