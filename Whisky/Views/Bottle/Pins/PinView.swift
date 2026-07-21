//
//  PinView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

struct PinView: View {
    @Bindable var bottle: Bottle
    @Bindable var program: Program
    @State var pin: PinnedProgram
    @Binding var path: NavigationPath
    var isSelected: Bool = false
    var onSelect: (() -> Void)?
    var onRun: (() -> Void)?

    @State private var image: Image?
    @State private var showRenameSheet = false
    @State private var name: String = ""
    @State private var opening: Bool = false
    @State private var launchCoordinator = ProgramLaunchCoordinator.shared
    @State private var isDropTargeted = false

    private var pinURL: URL? { pin.url ?? program.url }

    var body: some View {
        Button(action: handlePrimaryAction) {
            card
        }
        .buttonStyle(.plain)
        .help("点击启动 \(name) · 可拖拽排序")
        .draggable(program.url.absoluteString) {
            card
                .opacity(0.9)
                .frame(width: 120)
        }
        .dropDestination(for: String.self) { items, location in
            handleDrop(items, location)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .contextMenu {
            Button("运行", systemImage: "play.fill") {
                runProgram()
            }
            ProgramMenuView(program: program, path: $path)
            Divider()
            Button("前移", systemImage: "arrow.left") {
                bottle.movePin(program.url, by: -1)
            }
            Button("后移", systemImage: "arrow.right") {
                bottle.movePin(program.url, by: 1)
            }
            Button("移到最前", systemImage: "backward.end") {
                bottle.movePinToStart(program.url)
            }
            Button("移到最后", systemImage: "forward.end") {
                bottle.movePinToEnd(program.url)
            }
            Divider()
            Button("重命名", systemImage: "pencil.line") {
                showRenameSheet.toggle()
            }
            Button("在 Finder 中显示", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([program.url])
            }
            Button("取消固定", systemImage: "pin.slash", role: .destructive) {
                program.pinned = false
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameView("rename.pin.title", name: name) { newName in
                name = newName
            }
        }
        .task {
            name = pin.name
            guard let peFile = program.peFile else { return }
            image = await Task.detached {
                guard let nsImage = peFile.bestIcon() else { return nil as Image? }
                return Image(nsImage: nsImage)
            }.value
        }
        .onChange(of: name) {
            if let index = bottle.settings.pins.firstIndex(where: { $0.url == pin.url || $0.url == program.url }) {
                bottle.settings.pins[index].name = name
            }
        }
    }

    private var card: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        image
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(opening ? 1.15 : 1)
                .opacity(opening ? 0.2 : 1)

                Image(systemName: "play.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 18))
                    .offset(x: 4, y: 4)
            }
            Text(name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(width: 104, height: 110)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .fill(
                    isDropTargeted
                        ? Color.accentColor.opacity(0.22)
                        : (isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: MacBottleTheme.cardRadius, style: .continuous)
                .strokeBorder(
                    isDropTargeted || isSelected || launchCoordinator.isLaunching(programURL: program.url)
                        ? Color.accentColor.opacity(0.95)
                        : Color(nsColor: .separatorColor).opacity(0.35),
                    lineWidth: (isDropTargeted || isSelected
                        || launchCoordinator.isLaunching(programURL: program.url)) ? 2 : 1
                )
        }
        .overlay(alignment: .top) {
            if launchCoordinator.isLaunching(programURL: program.url) {
                Text("正在启动")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
            }
        }
    }

    private func handlePrimaryAction() {
        onSelect?()
        runProgram()
    }

    private func handleDrop(_ items: [String], _ location: CGPoint) -> Bool {
        guard let raw = items.first else { return false }
        let sourceURL: URL
        if let parsed = URL(string: raw), parsed.isFileURL {
            sourceURL = parsed
        } else if raw.hasPrefix("/") {
            sourceURL = URL(fileURLWithPath: raw)
        } else {
            return false
        }
        guard sourceURL.standardizedFileURL != program.url.standardizedFileURL else {
            return false
        }
        bottle.reorderPin(from: sourceURL, to: program.url)
        return true
    }

    func runProgram() {
        guard launchCoordinator.canStart(programURL: program.url) else {
            launchCoordinator.noteAlreadyLaunching(programName: program.name)
            return
        }

        withAnimation(.easeIn(duration: 0.25)) {
            opening = true
        } completion: {
            withAnimation(.easeOut(duration: 0.1)) {
                opening = false
            }
        }

        if let onRun {
            onRun()
        } else {
            program.run()
        }
    }
}
