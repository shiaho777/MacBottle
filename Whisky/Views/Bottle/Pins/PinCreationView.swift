//
//  PinCreationView.swift
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

struct PinCreationView: View {
    let bottle: Bottle

    @State private var projects: [URL] = []
    @State private var selectedProject: URL?
    @State private var selectedExe: URL?
    @State private var newPinName: String = ""
    @State private var isDuplicate: Bool = false

    @Environment(\.dismiss) private var dismiss

    private var availableExes: [URL] {
        guard let selectedProject else { return [] }
        return bottle.executables(inProject: selectedProject)
    }

    private var canSubmit: Bool {
        selectedExe != nil && !newPinName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    EmptyStateCard(
                        systemImage: "tray",
                        title: "pin.empty.title",
                        message: "pin.empty.message",
                        actionTitle: "pin.empty.action"
                    ) {
                        dismiss()
                    }
                } else {
                    pinForm
                }
            }
            .navigationTitle("pin.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                if !projects.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("pin.create") {
                            submit()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSubmit)
                        .alert("pin.error.title", isPresented: $isDuplicate) {
                        } message: {
                            Text("pin.error.duplicate.\(selectedExe?.lastPathComponent ?? "unknown")")
                        }
                    }
                }
            }
        }
        .onAppear {
            projects = bottle.workspaceProjects()
            if selectedProject == nil {
                selectedProject = projects.first
            }
        }
        .onChange(of: selectedProject, initial: true) { _, _ in
            selectedExe = availableExes.first
        }
        .onChange(of: selectedExe) { _, newValue in
            guard let newValue else { return }
            if newPinName.isEmpty {
                newPinName = newValue.deletingPathExtension().lastPathComponent
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: ViewWidth.small)
    }

    private var pinForm: some View {
        Form {
            Section("pin.project") {
                Picker("pin.project", selection: $selectedProject) {
                    ForEach(projects, id: \.self) { project in
                        Text(project.lastPathComponent).tag(project as URL?)
                    }
                }
            }

            Section("pin.executable") {
                if availableExes.isEmpty {
                    Text("pin.no.executable")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("pin.executable", selection: $selectedExe) {
                        ForEach(availableExes, id: \.self) { exe in
                            Text(exe.lastPathComponent).tag(exe as URL?)
                        }
                    }
                }
            }

            Section("pin.name") {
                TextField("pin.name", text: $newPinName)
            }
        }
        .formStyle(.grouped)
    }

    private func submit() {
        guard let selectedExe else { return }

        guard !bottle.settings.pins.contains(where: { $0.url == selectedExe }) else {
            isDuplicate = true
            return
        }

        bottle.settings.pins.append(PinnedProgram(name: newPinName, url: selectedExe))
        bottle.updateInstalledPrograms()
        dismiss()
    }
}

#Preview {
    PinCreationView(bottle: Bottle(bottleUrl: URL(filePath: "")))
}
