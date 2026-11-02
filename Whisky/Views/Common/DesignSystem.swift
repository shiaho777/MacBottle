//
//  DesignSystem.swift
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

struct PageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    var systemImage: String?

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            if let systemImage {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppColor.accent.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                }
                .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: AppSpacing.tiny) {
                Text(title)
                    .font(.title2.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
