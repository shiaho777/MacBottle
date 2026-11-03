//
//  WinetricksView.swift
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
import MacBottleKit

struct WinetricksView: View {
    var bottle: Bottle
    @State private var winetricks: [WinetricksCategory]?
    @State private var selectedTrick: UUID?
    @State private var selectedCategory: WinetricksCategories = .dlls
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var category: WinetricksCategory? {
        winetricks?.first { $0.category == selectedCategory }
    }

    private var filteredVerbs: [WinetricksVerb] {
        guard let category else { return [] }
        guard !query.isEmpty else { return category.verbs }
        return category.verbs.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedVerb: WinetricksVerb? {
        guard let selectedTrick else { return nil }
        return winetricks?.flatMap(\.verbs).first { $0.id == selectedTrick }
    }

    var body: some View {
        NavigationStack {
            Group {
                if winetricks == nil {
                    ProgressView("winetricks.loading")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Picker("winetricks.category", selection: $selectedCategory) {
                                ForEach(WinetricksCategories.allCases, id: \.self) { item in
                                    Text(NSLocalizedString(
                                        "winetricks.category.\(item.rawValue)",
                                        comment: ""
                                    ))
                                    .tag(item)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240, alignment: .leading)
                            TextField("winetricks.search", text: $query)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }
                        .padding(MacBottleTheme.pagePadding)

                        Divider()

                        if filteredVerbs.isEmpty {
                            ContentUnavailableView(
                                "winetricks.empty.title",
                                systemImage: "wrench.and.screwdriver",
                                description: Text("winetricks.empty.message")
                            )
                        } else {
                            Table(filteredVerbs, selection: $selectedTrick) {
                                TableColumn("winetricks.table.name", value: \.name)
                                TableColumn("winetricks.table.description", value: \.description)
                            }
                        }
                    }
                }
            }
            .navigationTitle("winetricks.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("button.run") {
                        runSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedVerb == nil)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            Task.detached {
                let tricks = await Winetricks.parseVerbs()
                await MainActor.run {
                    winetricks = tricks
                }
            }
        }
    }

    private func runSelected() {
        guard let trick = selectedVerb else { return }
        Task.detached {
            await Winetricks.runCommand(command: trick.name, bottle: bottle)
        }
        dismiss()
    }
}
