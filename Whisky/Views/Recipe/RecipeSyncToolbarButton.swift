//
//  RecipeSyncToolbarButton.swift
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

/// Toolbar button that drives the recipe-sync workflow.
///
/// Owns the `RecipeSyncController` so a single sync lifecycle is shared
/// across the entire main window, instead of being scoped to one bottle.
/// The diff sheet is presented from this view so clicking the button
/// either (a) opens the sheet immediately with a pending diff, or
/// (b) runs a check and opens the sheet once results arrive.
struct RecipeSyncToolbarButton: View {
    @State private var controller = RecipeSyncController()
    @State private var showUpToDate = false

    var body: some View {
        Button {
            controller.check()
        } label: {
            icon
                .help(helpText)
        }
        .disabled(isBusy)
        .sheet(item: $controller.pending) { pending in
            RecipeSyncView(controller: controller, pending: pending)
        }
        .onChange(of: controller.phase) { _, newValue in
            if newValue == .upToDate {
                showUpToDate = true
                // Auto-hide the "Up to date" tick after a moment so the
                // toolbar returns to its resting state.
                Task { [weak controller] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run {
                        if controller?.phase == .upToDate {
                            controller?.phase = .idle
                        }
                        showUpToDate = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch controller.phase {
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate where showUpToDate:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        default:
            Image(systemName: "arrow.triangle.2.circlepath.circle")
        }
    }

    private var isBusy: Bool {
        controller.phase == .checking
    }

    private var helpText: LocalizedStringKey {
        switch controller.phase {
        case .checking:
            return "Checking for recipe updates…"
        case .upToDate:
            return "Recipes are up to date"
        case .failed(let message):
            return "Recipe check failed: \(message)"
        default:
            return "Sync recipes from GitHub"
        }
    }
}
