//
//  ActivityCenterView.swift
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

struct ActivityCenterView: View {
    @Binding var selection: SidebarSelection?
    @State private var coordinator = ProgramLaunchCoordinator.shared
    @State private var bottles: [Bottle] = []
    @State private var refreshToken = 0

    private struct RunningBottle: Identifiable {
        let bottle: Bottle
        let count: Int
        var id: URL { bottle.url }
    }

    private var runningBottles: [RunningBottle] {
        _ = refreshToken
        return bottles.compactMap { bottle in
            let count = BottleProcessRegistry.shared.registeredProcesses(for: bottle).count
            return count > 0 ? RunningBottle(bottle: bottle, count: count) : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacBottleTheme.sectionSpacing) {
                header
                currentActivity
                runningSection
            }
            .padding(MacBottleTheme.pagePadding)
        }
        .navigationTitle("activity.title")
        .task {
            bottles = BottleVM.shared.bottles
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            PageHeader(
                title: "activity.title",
                subtitle: "activity.subtitle",
                systemImage: "waveform.path.ecg"
            )
            Button {
                bottles = BottleVM.shared.bottles
                refreshToken += 1
            } label: {
                Label("button.refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("button.refresh"))
        }
    }

    private var currentActivity: some View {
        SurfaceCard(padding: 16) {
            HStack(spacing: 14) {
                activityIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(activityTitle)
                        .font(.headline)
                    Text(activityMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if coordinator.phase.isActive {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var activityIcon: some View {
        switch coordinator.phase {
        case .idle:
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.secondary)
                .font(.title2)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
        default:
            Image(systemName: "play.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title2)
        }
    }

    private var activityTitle: String {
        switch coordinator.phase {
        case .idle: return String(localized: "activity.idle.title")
        case .warming: return String(localized: "bottle.launch.warming")
        case .provisioning: return String(localized: "bottle.launch.provisioning")
        case .launching: return String(localized: "bottle.launch.launching")
        case .launched: return String(localized: "bottle.launch.launched")
        case .failed: return String(localized: "activity.failed.title")
        }
    }

    private var activityMessage: String {
        switch coordinator.phase {
        case .idle:
            return String(localized: "activity.idle.message")
        case .warming(let bottleName):
            return bottleName
        case .provisioning(let programName, let detail):
            return "\(programName) · \(detail)"
        case .launching(let programName, _), .launched(let programName):
            return programName
        case .failed(let programName, let message):
            return "\(programName) · \(message)"
        }
    }

    @ViewBuilder
    private var runningSection: some View {
        VStack(alignment: .leading, spacing: MacBottleTheme.rowSpacing) {
            Text("activity.running")
                .font(.headline)
            if runningBottles.isEmpty {
                SurfaceCard(padding: 16) {
                    Text("activity.running.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(runningBottles) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.bottle.settings.name)
                                .font(.body.weight(.medium))
                            Text(
                                String(
                                    format: String(localized: "activity.running.count %lld"),
                                    entry.count
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("activity.openBottle") {
                            selection = .bottle(entry.bottle.url)
                        }
                        .buttonStyle(.borderless)
                        Button("bottle.bar.forceStop", role: .destructive) {
                            BottleForceStop.forceStop(bottle: entry.bottle, reason: "activity")
                            refreshToken += 1
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: MacBottleTheme.compactRadius, style: .continuous)
                            .fill(.background.secondary)
                    }
                }
            }
        }
    }
}
