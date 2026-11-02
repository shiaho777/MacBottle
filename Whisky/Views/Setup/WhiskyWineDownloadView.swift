//
//  WhiskyWineDownloadView.swift
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

import Observation
import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @State private var model = EngineDownloadModel()
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]

    var body: some View {
        VStack(spacing: 12) {
            Text("setup.whiskywine.download")
                .font(.title)
                .fontWeight(.bold)
            Text("setup.whiskywine.download.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.isDownloading || model.fraction > 0 {
                ProgressView(value: min(max(model.fraction, 0), 1), total: 1)
                    .padding(.horizontal)
                HStack {
                    Text(String(
                        format: String(localized: "setup.whiskywine.progress"),
                        Self.formatBytes(model.completedBytes),
                        Self.formatBytes(model.totalBytes)
                    ))
                    if model.speed > 0, model.totalBytes > model.completedBytes {
                        Text(String(
                            format: String(localized: "setup.whiskywine.eta"),
                            Self.formatRemaining(
                                bytes: model.totalBytes - model.completedBytes,
                                speed: model.speed
                            )
                        ))
                    }
                    Spacer()
                }
                .font(.subheadline)
                .monospacedDigit()
                .padding(.horizontal)
            }

            if let error = model.errorMessage {
                Text(verbatim: error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("setup.retry") {
                    model.start()
                }
            }
        }
        .frame(width: 420, height: 240)
        .onAppear {
            model.start()
        }
        .onDisappear {
            model.cancel()
        }
        .onChange(of: model.completedURL) { _, url in
            guard let url else { return }
            tarLocation = url
            path.append(.whiskyWineInstall)
        }
        .alert(
            "setup.engine.trust.title",
            isPresented: Binding(
                get: { model.awaitingTrust },
                set: { model.awaitingTrust = $0 }
            )
        ) {
            Button("setup.engine.trust.accept") {
                model.acceptChangedArchive()
            }
            Button("button.removeAlert.cancel", role: .cancel) {
                model.cancel()
            }
        } message: {
            if let message = model.errorMessage {
                Text(verbatim: message)
            }
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    private static func formatRemaining(bytes: Int64, speed: Double) -> String {
        guard speed > 0 else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .short
        return formatter.string(from: TimeInterval(Double(bytes) / speed)) ?? ""
    }
}

@MainActor
@Observable
final class EngineDownloadModel {
    static let sourceURL: URL = {
        guard let url = URL(string: "https://data.getwhisky.app/Wine/Libraries.tar.gz") else {
            preconditionFailure("invalid engine source URL")
        }
        return url
    }()

    var fraction: Double = 0
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var speed: Double = 0
    var isDownloading = false
    var errorMessage: String?
    var awaitingTrust = false
    var completedURL: URL?

    private var task: Task<Void, Never>?
    private var destination: URL?

    func start(acceptingChangedDigest: Bool = false) {
        guard !isDownloading else { return }
        isDownloading = true
        errorMessage = nil
        awaitingTrust = false
        completedURL = nil
        fraction = 0
        completedBytes = 0
        totalBytes = 0
        speed = 0

        let destination = FileManager.default.temporaryDirectory
            .appending(path: "WhiskyWine-\(UUID().uuidString).tar.gz")
        self.destination = destination

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await EngineDownloadService.shared.download(
                    from: Self.sourceURL,
                    to: destination,
                    acceptingChangedDigest: acceptingChangedDigest
                ) { progress in
                    Task { @MainActor [weak self] in
                        self?.apply(progress)
                    }
                }
                self.completedURL = url
            } catch let error as EngineArchiveTrustError {
                if case .digestChanged = error {
                    self.awaitingTrust = true
                }
                self.errorMessage = error.localizedDescription
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isDownloading = false
        }
    }

    func acceptChangedArchive() {
        awaitingTrust = false
        start(acceptingChangedDigest: true)
    }

    func cancel() {
        task?.cancel()
        task = nil
        isDownloading = false
        if let destination {
            try? FileManager.default.removeItem(at: destination)
        }
    }

    private func apply(_ progress: EngineDownloadProgress) {
        fraction = progress.fraction
        completedBytes = progress.completedBytes
        totalBytes = progress.totalBytes
        speed = progress.bytesPerSecond
    }
}
