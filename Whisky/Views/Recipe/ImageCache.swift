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
    private let diskRoot: URL
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let memoryLimit = 256

    init(diskRoot: URL? = nil) {
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
        try? FileManager.default.createDirectory(
            at: self.diskRoot,
            withIntermediateDirectories: true
        )
    }

    func data(for url: URL) async -> Data? {
        if let hit = memory[url] {
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
            if memory.count >= memoryLimit {
                memory.removeAll(keepingCapacity: true)
            }
            memory[url] = data
        }
        return data
    }

    private static func diskURL(for url: URL, root: URL) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return root.appending(path: String(format: "%016llx", hash))
    }

    private static func readFromDisk(url: URL, root: URL) -> Data? {
        let path = diskURL(for: url, root: root)
        return try? Data(contentsOf: path)
    }

    private static func downloadAndStore(url: URL, root: URL) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let session = URLSession(configuration: .default)
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
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
