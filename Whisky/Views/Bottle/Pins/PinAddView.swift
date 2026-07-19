//
//  PinAddView.swift
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

struct PinAddView: View {
    let bottle: Bottle
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: 52, height: 52)
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("添加固定")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(width: 104, height: 110)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                    .fill(.background.secondary.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            PinCreationView(bottle: bottle)
        }
    }
}

#Preview {
    PinAddView(bottle: Bottle(bottleUrl: URL(filePath: "")))
}
