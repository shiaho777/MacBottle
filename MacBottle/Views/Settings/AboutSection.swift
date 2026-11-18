//
//  AboutSection.swift
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

struct AboutSection: View {
    private var versionText: String {
        guard let version = AppUpdateChecker.currentVersion() else {
            return String(localized: "about.version.unknown")
        }
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    var body: some View {
        Section("settings.about.section") {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "MacBottle")
                        .font(.headline)
                    Text("about.tagline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(verbatim: "v\(versionText)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button("about.copyVersion") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(versionText, forType: .string)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 4)

            AboutDocumentLink(titleKey: "about.license", resource: "LICENSE", extension: "txt")
            AboutDocumentLink(titleKey: "about.notices", resource: "NOTICE", extension: "txt")
        }
    }
}

struct CommunitySection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("settings.community.section") {
            communityLink("community.website", "https://github.com/shiaho777/MacBottle")
            communityLink("community.feedback", "https://github.com/shiaho777/MacBottle/issues/new/choose")
            communityLink("community.contribute", "https://github.com/shiaho777/MacBottle/blob/main/CONTRIBUTING.md")
            communityLink("community.contributors", "https://github.com/shiaho777/MacBottle/graphs/contributors")
            communityLink("community.releases", "https://github.com/shiaho777/MacBottle/releases")
            Text("community.nonCode")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func communityLink(_ titleKey: LocalizedStringKey, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) {
                openURL(url)
            }
        } label: {
            HStack {
                Text(titleKey)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AboutDocumentLink: View {
    let titleKey: LocalizedStringKey
    let resource: String
    let `extension`: String

    @State private var showDocument = false

    var body: some View {
        Button {
            showDocument = true
        } label: {
            HStack {
                Text(titleKey)
                Spacer()
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDocument) {
            AboutDocumentView(titleKey: titleKey, resource: resource, extension: `extension`)
        }
    }
}

private struct AboutDocumentView: View {
    let titleKey: LocalizedStringKey
    let resource: String
    let `extension`: String

    @Environment(\.dismiss) private var dismiss

    private var documentText: String? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: `extension`) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(titleKey)
                    .font(.headline)
                Spacer()
                Button("button.ok") {
                    dismiss()
                }
            }
            .padding()
            Divider()
            if let documentText {
                ScrollView {
                    Text(verbatim: documentText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                Text("about.document.missing")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 560)
    }
}
