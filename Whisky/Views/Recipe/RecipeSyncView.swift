//
//  RecipeSyncView.swift
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

/// Modal sheet shown when the remote manifest publishes changes since the
/// user's last sync.
///
/// Presents each change as a row with a checkbox. The footer lets the
/// user sync every selected change in one click; empty selection disables
/// the primary action. The sheet dismisses itself on success.
struct RecipeSyncView: View {
    @ObservedObject var controller: RecipeSyncController
    let pending: RecipeSyncController.Pending

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            listBody
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recipe updates available")
                    .font(.headline)
                Text(verbatim: summaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(allSelected ? "Deselect all" : "Select all") {
                if allSelected {
                    controller.deselectAll()
                } else {
                    controller.selectAll()
                }
            }
            .buttonStyle(.link)
        }
        .padding(16)
    }

    private var listBody: some View {
        List(pending.result.changes) { change in
            ChangeRow(
                change: change,
                isSelected: Binding(
                    get: { controller.selectedIDs.contains(change.id) },
                    set: { _ in controller.toggle(change.id) }
                )
            )
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            if case .applying = controller.phase {
                ProgressView(
                    value: Double(controller.applyProgress.completed),
                    total: Double(max(controller.applyProgress.total, 1))
                )
                .frame(maxWidth: 200)
                Text(verbatim: "Downloading \(controller.applyProgress.completed) of "
                    + "\(controller.applyProgress.total)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .done = controller.phase {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("All changes applied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .failed(let message) = controller.phase {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(cancelLabel, role: .cancel) {
                controller.dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if !isDone {
                Button(primaryActionLabel) {
                    controller.applySelection()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(controller.selectedIDs.isEmpty || isApplying)
            }
        }
        .padding(16)
    }

    // MARK: - Derived

    private var summaryLine: String {
        let added = pending.result.changes.filter { $0.kind == .added }.count
        let updated = pending.result.changes.filter { $0.kind == .updated }.count
        let removed = pending.result.changes.filter { $0.kind == .removed }.count
        return "\(added) added · \(updated) updated · \(removed) removed"
    }

    private var allSelected: Bool {
        controller.selectedIDs.count == pending.result.changes.count
    }

    private var isApplying: Bool {
        if case .applying = controller.phase { return true }
        return false
    }

    private var isDone: Bool {
        if case .done = controller.phase { return true }
        return false
    }

    private var cancelLabel: LocalizedStringKey {
        isDone ? "Close" : "Cancel"
    }

    private var primaryActionLabel: LocalizedStringKey {
        controller.selectedIDs.count == pending.result.changes.count
            ? "Sync all"
            : "Sync selected (\(controller.selectedIDs.count))"
    }
}

// MARK: - Row

private struct ChangeRow: View {
    let change: RecipeChange
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)

            iconView
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: change.title)
                    .font(.body)
                Text(verbatim: change.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            KindBadge(kind: change.kind)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }

    @ViewBuilder
    private var iconView: some View {
        if let url = change.iconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "gamecontroller")
                .foregroundStyle(.secondary)
        }
    }
}

private struct KindBadge: View {
    let kind: RecipeChange.Kind

    var body: some View {
        Text(verbatim: label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch kind {
        case .added:   return "Added"
        case .updated: return "Updated"
        case .removed: return "Removed"
        }
    }

    private var color: Color {
        switch kind {
        case .added:   return .green
        case .updated: return .blue
        case .removed: return .red
        }
    }
}
