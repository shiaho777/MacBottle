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

/// Process-wide image cache for recipe cover art.
///
/// Two layers:
/// 1. **Memory (NSCache)** — hot images stay resident while the app is
///    running. Sized by count, not bytes, because Steam header art is
///    uniformly small (~100 KB).
/// 2. **Disk (Application Support)** — cached bytes survive relaunches.
///    Keyed by URL hash so we never need to parse query strings.
///
/// The shared instance backs `CachedAsyncImage`, which replaces SwiftUI's
/// built-in `AsyncImage` for recipe rows. `AsyncImage` is not cell-safe
/// inside `List`: every time a row scrolls in or out it rebuilds its
/// internal state and refetches the URL. That was the source of the
/// "icons reload on scroll" regression.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    // NSCache is thread-safe and auto-evicts under memory pressure, but
    // we still hand it off to the actor so reads and writes never race
    // against the download task coordinator.
    private let memory = NSCache<NSURL, NSImage>()
    private let diskRoot: URL
    private let lock = NSLock()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

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
        memory.countLimit = 256
        try? FileManager.default.createDirectory(at: self.diskRoot, withIntermediateDirectories: true)
    }

    /// Fetch an image for a URL, using the in-memory and on-disk caches
    /// before hitting the network. Concurrent requests for the same URL
    /// coalesce into a single download.
    func image(for url: URL) async -> NSImage? {
        if let hit = memory.object(forKey: url as NSURL) {
            return hit
        }

        let existing: Task<NSImage?, Never>?
        lock.lock()
        existing = inFlight[url]
        lock.unlock()
        if let existing {
            return await existing.value
        }

        let task = Task<NSImage?, Never> { [diskRoot] in
            if let onDisk = Self.readFromDisk(url: url, root: diskRoot) {
                return onDisk
            }
            return await Self.downloadAndStore(url: url, root: diskRoot)
        }
        lock.lock()
        inFlight[url] = task
        lock.unlock()
        let image = await task.value
        lock.lock()
        inFlight[url] = nil
        lock.unlock()
        if let image {
            memory.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    // MARK: - Disk helpers

    private static func diskURL(for url: URL, root: URL) -> URL {
        // SHA-ish filename from the absolute URL string. FNV-1a 64-bit
        // keeps the dependency footprint at zero while collisions are
        // astronomically unlikely for a few hundred icons.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return root.appending(path: String(format: "%016llx", hash))
    }

    private static func readFromDisk(url: URL, root: URL) -> NSImage? {
        let path = diskURL(for: url, root: root)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return NSImage(data: data)
    }

    private static func downloadAndStore(url: URL, root: URL) async -> NSImage? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let session = URLSession(configuration: .default)
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }

            // Persist before decoding so the bytes are durable regardless
            // of NSImage's ability to parse them.
            let path = diskURL(for: url, root: root)
            try? data.write(to: path, options: .atomic)

            return NSImage(data: data)
        } catch {
            Logger.wineKit.debug("ImageCache: fetch failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Remove every cached image, memory and disk. Intended for support
    /// tickets; the app itself never calls this.
    func purge() throws {
        memory.removeAllObjects()
        if FileManager.default.fileExists(atPath: diskRoot.path) {
            try FileManager.default.removeItem(at: diskRoot)
            try FileManager.default.createDirectory(at: diskRoot, withIntermediateDirectories: true)
        }
    }
}

/// Drop-in replacement for `AsyncImage` that reads through `ImageCache`
/// and therefore survives `List` cell recycling without refetching.
///
/// Usage:
///
///     CachedAsyncImage(url: recipe.iconURL) { image in
///         image.resizable().aspectRatio(contentMode: .fill)
///     } placeholder: {
///         ProgressView().controlSize(.small)
///     } failure: {
///         Image(systemName: "gamecontroller")
///     }
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
            if let image = await ImageCache.shared.image(for: url) {
                loaded = image
            } else {
                didFail = true
            }
        }
    }
}
