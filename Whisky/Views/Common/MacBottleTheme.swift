//
//  MacBottleTheme.swift
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

enum MacBottleTheme {
    static let cardRadius: CGFloat = 14
    static let compactRadius: CGFloat = 10
    static let gridSpacing: CGFloat = 14
    static let pagePadding: CGFloat = 20

    static var cardBackground: some ShapeStyle {
        .background.secondary
    }

    static func engineLabel(for engineID: String?) -> String {
        guard let engineID,
              let engine = WineEngineCatalog.engine(id: engineID) else {
            return "自动"
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
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
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
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                    .fill(.background.secondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
            }
    }
}

struct BottleHeroHeader: View {
    let bottle: Bottle

    private var engineID: String? {
        bottle.settings.engineID
    }

    private var pinCount: Int {
        bottle.settings.pins.count
    }

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text(bottle.settings.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                    Text(bottle.url.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        StatusPill(
                            title: MacBottleTheme.engineLabel(for: engineID),
                            systemImage: "cpu",
                            color: MacBottleTheme.engineColor(for: engineID)
                        )
                        StatusPill(
                            title: "\(pinCount) 固定",
                            systemImage: "pin.fill",
                            color: .orange
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
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct QuickActionTile: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        SurfaceCard(padding: 12) {
            HStack(spacing: 12) {
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
