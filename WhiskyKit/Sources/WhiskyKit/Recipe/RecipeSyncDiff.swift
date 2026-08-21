//
//  RecipeSyncDiff.swift
//  WhiskyKit
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

// MARK: - Change

/// A single change between what MacBottle currently knows about and what
/// the upstream repository is publishing. Each change is addressable by
/// `id` so the UI can offer per-row checkboxes alongside the "sync all"
/// button without inventing its own coordinate system.
public struct RecipeChange: Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        /// Remote has this recipe, local does not. Accepting adds it.
        case added
        /// Local has this recipe, remote no longer does. Accepting
        /// removes the local copy.
        case removed
        /// Both sides have it but the upstream blob sha differs.
        /// Accepting overwrites local with remote.
        case updated
    }

    public let kind: Kind
    public let id: String
    /// Best-effort human name for UI. Comes from whichever side has the
    /// recipe available — remote wins when both do.
    public let title: String
    /// Optional icon for the diff UI. Same fallback policy as `title`.
    public let iconURL: URL?
    /// Upstream index entry when one exists (added/updated). Used by the
    /// service to fetch the file bytes when the user accepts the change.
    public let remoteEntry: RecipeIndex.Entry?

    public init(
        kind: Kind,
        id: String,
        title: String,
        iconURL: URL? = nil,
        remoteEntry: RecipeIndex.Entry? = nil
    ) {
        self.kind = kind
        self.id = id
        self.title = title
        self.iconURL = iconURL
        self.remoteEntry = remoteEntry
    }
}

// MARK: - Diff

/// Pure computation that turns three inputs — the new remote index, the
/// previously cached remote snapshot, and the currently decoded recipes —
/// into a flat list of changes the UI can render.
///
/// Kept as a `enum` namespace (no instances) because it holds no state.
/// This keeps it trivially testable and lets the sync service decide
/// which snapshot represents "what the user has right now".
public enum RecipeSyncDiff {

    /// Compute the diff.
    ///
    /// - Parameters:
    ///   - remoteIndex: the freshly-fetched remote manifest.
    ///   - localEntries: the manifest of what the client last accepted.
    ///     Typically the previously cached remote index. If the client
    ///     has never synced, pass `nil`.
    ///   - knownRecipes: recipes currently decoded in the app,
    ///     keyed by id. Used only to enrich change rows with titles and
    ///     icons for the diff UI. Can be empty.
    /// - Returns: changes sorted by kind (added → updated → removed) then
    ///   by id, so the UI order is deterministic across runs.
    public static func compute(
        remoteIndex: RecipeIndex,
        localEntries: [RecipeIndex.Entry]?,
        knownRecipes: [String: Recipe]
    ) -> [RecipeChange] {
        let localByID = Dictionary(
            (localEntries ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let remoteByID = Dictionary(
            remoteIndex.recipes.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var changes: [RecipeChange] = []

        // Added: in remote, not in local.
        for (id, remote) in remoteByID where localByID[id] == nil {
            let known = knownRecipes[id]
            changes.append(RecipeChange(
                kind: .added,
                id: id,
                title: known?.title ?? id,
                iconURL: known?.iconURL,
                remoteEntry: remote
            ))
        }

        // Removed: in local, not in remote.
        for (id, _) in localByID where remoteByID[id] == nil {
            let known = knownRecipes[id]
            changes.append(RecipeChange(
                kind: .removed,
                id: id,
                title: known?.title ?? id,
                iconURL: known?.iconURL,
                remoteEntry: nil
            ))
        }

        // Updated: in both but blob sha differs.
        for (id, remote) in remoteByID {
            guard let local = localByID[id], local.sha != remote.sha else { continue }
            let known = knownRecipes[id]
            changes.append(RecipeChange(
                kind: .updated,
                id: id,
                title: known?.title ?? id,
                iconURL: known?.iconURL,
                remoteEntry: remote
            ))
        }

        return changes.sorted(by: Self.deterministicOrder)
    }

    /// Deterministic order: kind then id. `.added` first so the UI puts
    /// new games at the top where users look first.
    private static func deterministicOrder(_ lhs: RecipeChange, _ rhs: RecipeChange) -> Bool {
        func rank(_ kind: RecipeChange.Kind) -> Int {
            switch kind {
            case .added:   return 0
            case .updated: return 1
            case .removed: return 2
            }
        }
        if rank(lhs.kind) != rank(rhs.kind) {
            return rank(lhs.kind) < rank(rhs.kind)
        }
        return lhs.id < rhs.id
    }
}
