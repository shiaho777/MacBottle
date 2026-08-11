//
//  WorkspaceImportView.swift
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

struct WorkspaceImportView: View {
    let bottle: Bottle

    @State private var sourceURL: URL?
    @State private var sourcePath: String = ""
    @State private var copyIntoBottle: Bool = true

    @State private var launchMode: LaunchMode = .file
    @State private var launchFileURL: URL?
    @State private var launchFilePath: String = ""
    @State private var launchCommand: String = ""

    @State private var entryName: String = ""
    @State private var importError: String?

    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        guard sourceURL != nil, !entryName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch launchMode {
        case .file: return launchFileURL != nil
        case .command: return !launchCommand.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("workspace.source") {
                    ActionView(
                        text: "workspace.source.pick",
                        subtitle: sourcePath,
                        actionName: "create.browse"
                    ) {
                        pickSource()
                    }
                    if sourceURL != nil {
                        Toggle("workspace.copyIntoBottle", isOn: $copyIntoBottle)
                    }
                }

                Section("workspace.launchEntry") {
                    Picker("workspace.launchMode", selection: $launchMode) {
                        Text("workspace.launchMode.file").tag(LaunchMode.file)
                        Text("workspace.launchMode.command").tag(LaunchMode.command)
                    }
                    .pickerStyle(.segmented)

                    switch launchMode {
                    case .file:
                        ActionView(
                            text: "workspace.launchFile",
                            subtitle: launchFilePath,
                            actionName: "create.browse"
                        ) {
                            pickLaunchFile()
                        }
                    case .command:
                        TextField("workspace.launchCommand.placeholder", text: $launchCommand)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                }

                Section("workspace.entryName") {
                    TextField("workspace.entryName.placeholder", text: $entryName)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("workspace.import.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("workspace.import.create") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                }
            }
            .onChange(of: sourceURL, initial: true) { _, newValue in
                guard let newValue else { return }
                sourcePath = newValue.prettyPath(bottle)
                if entryName.isEmpty ||
                    entryName == newValue.deletingPathExtension().lastPathComponent {
                    entryName = newValue.deletingPathExtension().lastPathComponent
                }
                launchFileURL = nil
                launchFilePath = ""
            }
            .alert("workspace.import.failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("button.ok") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: ViewWidth.small)
    }

    private func pickSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.begin { result in
            if result == .OK, let url = panel.urls.first {
                sourceURL = url
            }
        }
    }

    private func pickLaunchFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat")
        ]
        panel.directoryURL = sourceURL ?? bottle.url.appending(path: "drive_c")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.begin { result in
            if result == .OK, let url = panel.urls.first {
                launchFileURL = url
                launchFilePath = url.prettyPath(bottle)
            }
        }
    }

    private func submit() {
        guard let source = sourceURL, canSubmit else { return }

        let imports = bottle.url.appending(path: "drive_c").appending(path: "MacBottleImports")
        var entryURL: URL

        if copyIntoBottle {
            do {
                try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
                let dest = imports.appending(path: source.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: source, to: dest)
                entryURL = resolvedEntryURL(afterCopyingTo: dest, from: source)
            } catch {
                importError = error.localizedDescription
                return
            }
        } else {
            switch launchMode {
            case .file:
                entryURL = launchFileURL ?? source
            case .command:
                entryURL = source
            }
        }

        let program = Program(url: entryURL, bottle: bottle)
        var settings = program.settings
        settings.launchMode = launchMode
        if launchMode == .command {
            settings.launchCommand = launchCommand
        }
        program.settings = settings

        bottle.settings.pins.append(PinnedProgram(name: entryName, url: entryURL))
        bottle.updateInstalledPrograms()
        dismiss()
    }

    private func resolvedEntryURL(afterCopyingTo dest: URL, from source: URL) -> URL {
        switch launchMode {
        case .file:
            guard let file = launchFileURL else { return dest }
            let sourcePath = source.path(percentEncoded: false)
            let filePath = file.path(percentEncoded: false)
            if filePath.hasPrefix(sourcePath + "/") {
                let relative = String(filePath.dropFirst(sourcePath.count + 1))
                return dest.appending(path: relative)
            }
            return file
        case .command:
            return dest
        }
    }
}

#Preview {
    WorkspaceImportView(bottle: Bottle(bottleUrl: URL(filePath: "")))
}
