//
//  EngineInstallView.swift
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
import MacBottleKit

struct EngineInstallView: View {
    @State var installing: Bool = true
    @State private var errorMessage: String?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.install")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.install.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if installing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                } else if errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                }
                Spacer()
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("setup.retry") {
                        install()
                    }
                }
            }
            Spacer()
        }
        .frame(width: 520, height: 360)
        .onAppear {
            install()
        }
    }

    private func install() {
        installing = true
        errorMessage = nil
        let tarLocation = self.tarLocation
        Task.detached {
            do {
                try EngineInstaller.install(from: tarLocation)
                await MainActor.run {
                    installing = false
                }
                try? await Task.sleep(for: .seconds(1))
                await proceed()
            } catch {
                await MainActor.run {
                    installing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func proceed() {
        showSetup = false
    }
}
