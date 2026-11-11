//
//  DesignSystem.swift
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

import SwiftUI
import MacBottleKit

/// The single spacing scale. New screens should use these names instead of
/// hardcoded paddings; `MacBottleTheme` keeps aliases for older views.
enum AppSpacing {
    static let tiny: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
    static let doubleExtraLarge: CGFloat = 32

    static let page: CGFloat = 20
    static let section: CGFloat = 18
    static let grid: CGFloat = 14
}

enum AppRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
}

/// Semantic status colours. Using these keeps success/warning/danger
/// consistent and makes a future theme swap a one-file change.
enum AppColor {
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.blue
    static let accent = Color.accentColor
    static let neutral = Color.secondary
}

enum AppMotion {
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let quick = Animation.easeOut(duration: 0.16)

    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : standard
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var trailingTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailingTitle, let action {
                Button(trailingTitle, action: action)
                    .buttonStyle(.link)
            }
        }
    }
}

struct StatusBanner: View {
    let tint: Color
    let systemImage: String
    let title: String
    let message: String
    var showsProgress: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.small)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(tint.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Surfaces

/// A quiet branded background for detail panes. The accent wash is
/// deliberately weak: it gives the window depth without competing with
/// cover art or status colors.
struct AppBackground: View {
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [tint.opacity(0.075), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 680
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.018)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: value)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(.background.secondary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppFilterChip: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    var count: Int?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count {
                    Text(verbatim: "\(count)")
                        .monospacedDigit()
                        .opacity(0.72)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                Capsule().fill(
                    isSelected
                        ? Color.accentColor
                        : (hovering
                            ? Color.accentColor.opacity(0.10)
                            : Color(nsColor: .controlBackgroundColor))
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    isSelected
                        ? Color.white.opacity(0.16)
                        : Color(nsColor: .separatorColor).opacity(0.35),
                    lineWidth: 0.5
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.quick, value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Badges

struct CompatibilityBadge: View {
    let tier: CompatibilityTier

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tier.symbol)
                .font(.caption2.weight(.bold))
            Text(verbatim: tier.localizedName)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(tier.tint)
        .background(tier.tint.opacity(0.14), in: Capsule())
        .overlay {
            Capsule().strokeBorder(tier.tint.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: tier.localizedName))
    }
}

struct RendererBadge: View {
    let renderer: RecipeRenderer

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: renderer.symbol)
                .font(.caption2.weight(.bold))
            Text(verbatim: renderer.displayName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(.secondary)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: renderer.displayName))
    }
}

extension CompatibilityTier {
    var tint: Color {
        switch self {
        case .platinum: return .cyan
        case .gold: return .yellow
        case .silver: return .gray
        case .bronze: return .orange
        case .broken: return .red
        }
    }

    var symbol: String {
        switch self {
        case .platinum: return "sparkles"
        case .gold: return "star.fill"
        case .silver: return "circle.lefthalf.filled"
        case .bronze: return "exclamationmark.triangle.fill"
        case .broken: return "xmark.octagon.fill"
        }
    }
}

extension RecipeRenderer {
    var displayName: String {
        switch self {
        case .d3dmetal: return "D3DMetal"
        case .dxvk: return "DXVK"
        case .dxmt: return "DXMT"
        case .vkd3d: return "vkd3d"
        case .moltenvk: return "MoltenVK"
        case .wined3d: return "WineD3D"
        }
    }

    var symbol: String {
        switch self {
        case .d3dmetal: return "sparkles"
        case .dxvk: return "hare.fill"
        case .dxmt: return "bolt.fill"
        case .vkd3d: return "cube.fill"
        case .moltenvk: return "flame.fill"
        case .wined3d: return "square.stack.3d.up.fill"
        }
    }
}
