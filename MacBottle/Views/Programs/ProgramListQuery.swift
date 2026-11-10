//
//  ProgramListQuery.swift
//  MacBottle
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

import MacBottleKit
import SwiftUI

enum ProgramsPane: String, CaseIterable, Identifiable {
    case library
    case recent
    case blocklist

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .library: return "programs.pane.library"
        case .recent: return "programs.pane.recent"
        case .blocklist: return "programs.pane.blocklist"
        }
    }
}

enum ProgramFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case unpinned
    case x64
    case x86
    case games
    case tools

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: return "programs.filter.all"
        case .pinned: return "programs.filter.pinned"
        case .unpinned: return "programs.filter.unpinned"
        case .x64: return "programs.filter.x64"
        case .x86: return "programs.filter.x86"
        case .games: return "programs.filter.games"
        case .tools: return "programs.filter.tools"
        }
    }
}

enum ProgramSort: String, CaseIterable, Identifiable {
    case pinnedFirst
    case recent
    case name
    case folder
    case architecture

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pinnedFirst: return "programs.sort.pinnedFirst"
        case .recent: return "programs.sort.recent"
        case .name: return "programs.sort.name"
        case .folder: return "programs.sort.folder"
        case .architecture: return "programs.sort.architecture"
        }
    }
}

enum ProgramLayout: String, CaseIterable, Identifiable {
    case flat
    case folders

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .flat: return "programs.layout.flat"
        case .folders: return "programs.layout.folders"
        }
    }

    var systemImage: String {
        switch self {
        case .flat: return "list.bullet"
        case .folders: return "folder"
        }
    }
}

struct ProgramFolderGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let programs: [Program]
}

/// Pure filtering and ordering for the program list, kept out of the
/// view so it can be reasoned about (and benchmarked) without SwiftUI.
@MainActor
struct ProgramListQuery {
    var filter: ProgramFilter = .all
    var sort: ProgramSort = .pinnedFirst
    var searchText: String = ""
    var hideSystemNoise: Bool = true

    func filtered(from programs: [Program]) -> [Program] {
        var items = programs

        if hideSystemNoise {
            items = items.filter { !Self.isSystemNoise($0) }
        }
        if !searchText.isEmpty {
            items = items.filter { matchesSearch($0) }
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

        return sorted(items)
    }

    func recent(from programs: [Program]) -> [Program] {
        var items = programs.filter { $0.settings.lastLaunchedAt != nil }
        if hideSystemNoise {
            items = items.filter { !Self.isSystemNoise($0) }
        }
        if !searchText.isEmpty {
            items = items.filter { matchesSearch($0) }
        }
        return items.sorted {
            ($0.settings.lastLaunchedAt ?? .distantPast) > ($1.settings.lastLaunchedAt ?? .distantPast)
        }
    }

    func folderGroups(from filtered: [Program], bottle: Bottle) -> [ProgramFolderGroup] {
        let grouped = Dictionary(grouping: filtered) { $0.url.deletingLastPathComponent() }
        return grouped.keys.sorted {
            $0.path(percentEncoded: false).localizedCaseInsensitiveCompare($1.path(percentEncoded: false))
                == .orderedAscending
        }.compactMap { folderURL in
            guard let items = grouped[folderURL] else { return nil }
            return ProgramFolderGroup(
                id: folderURL.path(percentEncoded: false),
                title: folderURL.lastPathComponent,
                subtitle: folderURL.prettyPath(bottle),
                programs: sorted(items)
            )
        }
    }

    func sorted(_ items: [Program]) -> [Program] {
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
            // `peFile` stats the file, so read it once per item instead of
            // once per comparison; a comparator-local lookup turned an
            // O(n log n) sort into thousands of syscalls.
            let architecture = Dictionary(
                uniqueKeysWithValues: items.map {
                    ($0.id, $0.peFile?.architecture.toString() ?? "zzz")
                }
            )
            items.sort {
                let left = architecture[$0.id] ?? "zzz"
                let right = architecture[$1.id] ?? "zzz"
                if left != right { return left < right }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return items
    }

    private func matchesSearch(_ program: Program) -> Bool {
        program.name.localizedCaseInsensitiveContains(searchText)
            || program.url.path(percentEncoded: false).localizedCaseInsensitiveContains(searchText)
    }

    static func isInstallerOrTool(_ program: Program) -> Bool {
        let name = program.name.lowercased()
        let markers = [
            "setup", "install", "uninstall", "unins", "update", "patch",
            "redist", "vcredist", "directx", "dotnet", "launcher_uninstall",
            "crash", "report", "helper", "service"
        ]
        return markers.contains { name.contains($0) }
    }

    static func isSystemNoise(_ program: Program) -> Bool {
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
