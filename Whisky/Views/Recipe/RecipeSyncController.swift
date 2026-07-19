//
//  RecipeSyncController.swift
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

import Foundation
import Observation
import SwiftUI
import WhiskyKit
import os.log

/// Observable state holder for the recipe-sync sheet.
///
/// Owns the background check, exposes the diff to the view, and
/// orchestrates applying the user's selection. All state mutations happen
/// on the main actor so SwiftUI can observe them without extra hops.
@MainActor
@Observable
final class RecipeSyncController {
    enum Phase: Equatable {
        case idle
        case checking
        case reviewing           // diff ready, awaiting user
        case applying
        case done
        case upToDate            // check completed, nothing to sync
        case failed(message: String)
    }

    /// Full payload ready for the sheet. Identifiable so the sheet host
    /// can use `.sheet(item:)` to present exactly when a non-empty diff
    /// arrives.
    struct Pending: Identifiable {
        let id = UUID()
        let result: RecipeSyncService.CheckResult
    }

    var phase: Phase = .idle
    var pending: Pending?
    var selectedIDs: Set<String> = []
    var applyProgress: (completed: Int, total: Int) = (0, 0)
    /// Last time `check()` completed, successfully or not. The toolbar
    /// uses this to show "Last checked X ago" in its tooltip.
    var lastCheckedAt: Date?

    private let service: RecipeSyncService
    private let store: RecipeStore

    init(
        service: RecipeSyncService = RecipeSyncService(),
        store: RecipeStore = .shared
    ) {
        self.service = service
        self.store = store
    }

    /// Trigger a check. Always runs — the user explicitly asked for it
    /// by clicking the toolbar button, so we never throttle or skip.
    func check() {
        // Re-entrant clicks while a check is already in flight are
        // swallowed so the user doesn't spawn parallel requests.
        guard !isBusy else { return }

        phase = .checking
        Task { [weak self] in
            guard let self else { return }
            await self.performCheck()
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .checking, .applying:
            return true
        case .idle, .reviewing, .done, .upToDate, .failed:
            return false
        }
    }

    private func performCheck() async {
        do {
            let known = store.loadAll()
            let result = try await service.check(knownRecipes: known)
            lastCheckedAt = Date()
            if result.changes.isEmpty {
                self.phase = .upToDate
                self.pending = nil
                return
            }
            self.pending = Pending(result: result)
            // Default to all selected so "Sync all" is one tap away.
            self.selectedIDs = Set(result.changes.map(\.id))
            self.phase = .reviewing
        } catch {
            Logger.wineKit.error(
                "RecipeSyncController: check failed: \(error.localizedDescription)"
            )
            lastCheckedAt = Date()
            self.phase = .failed(message: error.localizedDescription)
            self.pending = nil
        }
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectAll() {
        guard let pending else { return }
        selectedIDs = Set(pending.result.changes.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    /// Apply selected changes. Cleans up the pending state and
    /// invalidates the recipe cache so UI pickers refresh.
    func applySelection() {
        guard let pending, !selectedIDs.isEmpty else { return }
        let selected = pending.result.changes.filter { selectedIDs.contains($0.id) }

        phase = .applying
        applyProgress = (0, selected.count)

        Task { [weak self] in
            guard let self else { return }
            await self.performApply(selected: selected, context: pending.result)
        }
    }

    private func performApply(
        selected: [RecipeChange],
        context: RecipeSyncService.CheckResult
    ) async {
        do {
            let outcomes = try await service.apply(
                changes: selected,
                remoteIndex: context.remoteIndex,
                newETag: context.newETag
            )
            applyProgress = (outcomes.count, selected.count)

            let failed = outcomes.filter { !$0.success }
            if failed.isEmpty {
                phase = .done
            } else {
                phase = .failed(
                    message: "Applied \(outcomes.count - failed.count) of \(outcomes.count); \(failed.count) failed."
                )
            }

            // Whether fully or partially applied, refresh the store so
            // the program pickers pick up new recipes. Keep `pending`
            // populated so the sheet stays up showing the final status
            // — `dismiss()` clears it when the user is ready to close.
            store.invalidateCache()
            NotificationCenter.default.post(name: .macbottleRecipesChanged, object: nil)
            selectedIDs.removeAll()
        } catch {
            Logger.wineKit.error(
                "RecipeSyncController: apply failed: \(error.localizedDescription)"
            )
            phase = .failed(message: error.localizedDescription)
        }
    }

    func dismiss() {
        pending = nil
        selectedIDs.removeAll()
        phase = .idle
    }
}
