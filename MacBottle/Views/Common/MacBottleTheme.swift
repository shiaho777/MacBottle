//
//  MacBottleTheme.swift
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

import AppKit
import SwiftUI
import MacBottleKit

enum MacBottleTheme {
    static let cardRadius: CGFloat = 14
    static let compactRadius: CGFloat = 10
    static let tileRadius: CGFloat = 12

    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 18
    static let gridSpacing: CGFloat = 14
    static let contentSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let tightSpacing: CGFloat = 6

    static let heroIconSize: CGFloat = 64
    static let rowIconSize: CGFloat = 40

    static let hairline: CGFloat = 1
    static let borderOpacity: Double = 0.35
    static let tintFillOpacity: Double = 0.12
    static let tintBorderOpacity: Double = 0.28
    static let badgeFillOpacity: Double = 0.18

    static var cardBackground: some ShapeStyle {
        .background.secondary
    }
    static func engineLabel(for engineID: String?) -> String {
        guard let engineID,
              let engine = WineEngineCatalog.engine(id: engineID) else {
            return String(localized: "engine.auto")
        }
        if engineID == WineEngineCatalog.d3dMetalIdentifier {
            return "D3DMetal"
        }
        if engineID == WineEngineCatalog.modernIdentifier {
            return "Modern"
        }
        return engine.displayName
    }

    static func engineColor(for engineID: String?) -> Color {
        guard let engineID else { return .secondary }
        if engineID == WineEngineCatalog.d3dMetalIdentifier {
            return .purple
        }
        if engineID == WineEngineCatalog.modernIdentifier {
            return .blue
        }
        return .secondary
    }
}

struct StatusPill: View {
    let title: String
    var systemImage: String?
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(MacBottleTheme.badgeFillOpacity), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: MacBottleTheme.gridSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
struct SurfaceCard<Content: View>: View {
    var radius: CGFloat = MacBottleTheme.cardRadius
    var padding: CGFloat = MacBottleTheme.contentSpacing
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.background.secondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.separator.opacity(MacBottleTheme.borderOpacity), lineWidth: MacBottleTheme.hairline)
            }
    }
}

struct BottleHeroHeader: View {
    let bottle: Bottle

    private var engineID: String? {
        bottle.settings.engineID
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)
            .shadow(color: Color.accentColor.opacity(0.30), radius: 14, y: 6)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(bottle.settings.name)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .lineLimit(1)
                    if !bottle.isAvailable {
                        StatusPill(
                            title: String(localized: "bottle.unavailable.title"),
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
                } label: {
                    Label("button.showInFinder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(bottle.url.path(percentEncoded: false))

                HStack(spacing: 6) {
                    StatusPill(
                        title: MacBottleTheme.engineLabel(for: engineID),
                        systemImage: "cpu",
                        color: MacBottleTheme.engineColor(for: engineID)
                    )
                    StatusPill(
                        title: bottle.settings.windowsVersion.pretty(),
                        systemImage: "desktopcomputer",
                        color: .secondary
                    )
                    if bottle.settings.dxvk {
                        StatusPill(title: "DXVK", systemImage: "hare.fill", color: .green)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 8)
        }
        .padding(20)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.16),
                                Color.accentColor.opacity(0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(Color.accentColor.opacity(0.055))
                    .offset(x: 34, y: -34)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 0.5)
        }
    }

}

struct QuickActionTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let subtitle: LocalizedStringKey

    var body: some View {
        SurfaceCard(padding: MacBottleTheme.tileRadius) {
            HStack(spacing: MacBottleTheme.contentSpacing) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

extension CompatibilityTier {
    var localizedName: String {
        switch self {
        case .platinum: return String(localized: "compatibility.platinum")
        case .gold:     return String(localized: "compatibility.gold")
        case .silver:   return String(localized: "compatibility.silver")
        case .bronze:   return String(localized: "compatibility.bronze")
        case .broken:   return String(localized: "compatibility.broken")
        }
    }
}
