//
//  ImageCache.swift
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
import AppKit
import WhiskyKit
import os.log

actor ImageCache {
    static let shared = ImageCache()

    private var memory: [URL: Data] = [:]
    private var memoryOrder: [URL] = []
    private let diskRoot: URL
    private let maxDiskBytes: Int64
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let memoryLimit = 256
    private var lastDiskPrune = Date.distantPast

    init(diskRoot: URL? = nil, maxDiskBytes: Int64 = 512 * 1024 * 1024) {
        if let diskRoot {
            self.diskRoot = diskRoot
        } else {
            let urls = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )
            guard let base = urls.first else {
                preconditionFailure("application support directory missing")
            }
            self.diskRoot = base
                .appending(path: Bundle.whiskyBundleIdentifier)
                .appending(path: "ImageCache")
        }
        self.maxDiskBytes = maxDiskBytes
        try? FileManager.default.createDirectory(
            at: self.diskRoot,
            withIntermediateDirectories: true
        )
    }

    func data(for url: URL) async -> Data? {
        if let hit = memory[url] {
            touch(url)
            return hit
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<Data?, Never> { [diskRoot] in
            if let onDisk = Self.readFromDisk(url: url, root: diskRoot) {
                return onDisk
            }
            return await Self.downloadAndStore(url: url, root: diskRoot)
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if let data {
            storeInMemory(data, for: url)
            pruneDiskIfNeeded()
        }
        return data
    }

    private func touch(_ url: URL) {
        memoryOrder.removeAll { $0 == url }
        memoryOrder.append(url)
    }

    private func storeInMemory(_ data: Data, for url: URL) {
        if memory[url] == nil, memory.count >= memoryLimit,
           let oldest = memoryOrder.first {
            memory.removeValue(forKey: oldest)
            memoryOrder.removeFirst()
        }
        memory[url] = data
        touch(url)
    }

    /// Keep the disk cache bounded. Without this, every distinct recipe
    /// icon ever viewed stayed on disk forever.
    func pruneDiskIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastDiskPrune) > 300 else { return }
        lastDiskPrune = now

        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: diskRoot,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var files: [(url: URL, size: Int64, modified: Date)] = []
        for entry in entries {
            guard let values = try? entry.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            ), let size = values.fileSize else { continue }
            files.append((entry, Int64(size), values.contentModificationDate ?? .distantPast))
        }
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxDiskBytes else { return }

        for file in files.sorted(by: { $0.modified < $1.modified }) {
            guard total > maxDiskBytes else { break }
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }

    private static func diskURL(for url: URL, root: URL) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return root.appending(path: String(format: "%016llx", hash))
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    private static func readFromDisk(url: URL, root: URL) -> Data? {
        let path = diskURL(for: url, root: root)
        guard let data = try? Data(contentsOf: path) else { return nil }
        if NSImage(data: data) == nil {
            try? FileManager.default.removeItem(at: path)
            return nil
        }
        return data
    }

    private static func downloadAndStore(url: URL, root: URL) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard NSImage(data: data) != nil else {
                Logger.wineKit.debug(
                    "ImageCache: discarding non-image response from \(url.host ?? "unknown", privacy: .public)"
                )
                return nil
            }

            let path = diskURL(for: url, root: root)
            try? data.write(to: path, options: .atomic)
            return data
        } catch {
            Logger.wineKit.debug(
                "ImageCache: fetch failed for \(url.lastPathComponent): \(error.localizedDescription)"
            )
            return nil
        }
    }

    func purge() throws {
        memory.removeAll()
        memoryOrder.removeAll()
        if FileManager.default.fileExists(atPath: diskRoot.path) {
            try FileManager.default.removeItem(at: diskRoot)
            try FileManager.default.createDirectory(
                at: diskRoot,
                withIntermediateDirectories: true
            )
        }
    }
}

struct CachedAsyncImage<Success: View, Placeholder: View, Failure: View>: View {
    let url: URL?
    let success: (Image) -> Success
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @State private var loaded: NSImage?
    @State private var didFail: Bool = false

    init(
        url: URL?,
        @ViewBuilder success: @escaping (Image) -> Success,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.success = success
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            if let loaded {
                success(Image(nsImage: loaded))
            } else if didFail {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                didFail = true
                return
            }
            loaded = nil
            didFail = false
            if let data = await ImageCache.shared.data(for: url),
               let image = NSImage(data: data) {
                loaded = image
            } else {
                didFail = true
            }
        }
    }
}
