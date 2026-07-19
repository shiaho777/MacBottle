//
//  SteamClientSeeder.swift
//  WhiskyKit
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

import Foundation
import os.log

public struct SteamClientSeedResult: Sendable {
    public let version: String
    public let packageCount: Int
    public let totalBytes: Int64
    public let steamRoot: URL
}

public enum SteamClientSeederError: Error, LocalizedError {
    case manifestUnavailable
    case noPackages
    case unzipFailed(String)
    case missingSteamExecutable

    public var errorDescription: String? {
        switch self {
        case .manifestUnavailable:
            return "Could not fetch Steam client manifest."
        case .noPackages:
            return "Steam client manifest contained no packages."
        case .unzipFailed(let name):
            return "Failed to extract Steam package \(name)."
        case .missingSteamExecutable:
            return "Steam.exe missing after native seed."
        }
    }
}

public final class SteamClientSeeder: @unchecked Sendable {
    public static let shared = SteamClientSeeder()

    public static let manifestURL: URL = {
        guard let url = URL(string: "https://media.steampowered.com/client/steam_client_win32") else {
            preconditionFailure("SteamClientSeeder.manifestURL is invalid")
        }
        return url
    }()

    public static let packageBaseURL: URL = {
        guard let url = URL(string: "https://media.steampowered.com/client/") else {
            preconditionFailure("SteamClientSeeder.packageBaseURL is invalid")
        }
        return url
    }()

    private let store: ContentStore
    private let downloader: ChunkedDownloader

    public init(
        store: ContentStore = .default(),
        downloader: ChunkedDownloader = ChunkedDownloader(maxConcurrent: 10)
    ) {
        self.store = store
        self.downloader = downloader
    }

    public func seed(
        intoBottle bottleURL: URL,
        onProgress: (@Sendable (DownloadProgress, String) -> Void)? = nil
    ) async throws -> SteamClientSeedResult {
        onProgress?(
            DownloadProgress(
                completedUnits: 0, totalUnits: 1, completedFiles: 0, totalFiles: 1,
                bytesPerSecond: 0, currentFile: "manifest"
            ),
            "Fetching Steam client manifest (native)…"
        )

        let manifest = try await fetchManifest()
        let manifestData = manifest.data
        let packages = manifest.packages
        let version = manifest.version
        let manifestText = manifest.text
        guard !packages.isEmpty else { throw SteamClientSeederError.noPackages }

        let versionDir = store.steamClientVersionDir(version)
        let packagesDir = versionDir.appending(path: "packages")
        let extractDir = versionDir.appending(path: "extract")
        try store.ensureDir(packagesDir)
        try store.ensureDir(extractDir)

        try manifestData.write(to: packagesDir.appending(path: "steam_client_win32"), options: .atomic)
        try manifestText.write(
            to: packagesDir.appending(path: "steam_client_win32.vdf.txt"),
            atomically: true,
            encoding: .utf8
        )

        let jobs: [DownloadJob] = packages.map { pkg in
            DownloadJob(
                url: SteamClientSeeder.packageBaseURL.appending(path: pkg.fileName),
                destination: packagesDir.appending(path: pkg.fileName),
                expectedSize: pkg.size
            )
        }

        let totalBytes = packages.reduce(Int64(0)) { $0 + $1.size }
        onProgress?(
            DownloadProgress(
                completedUnits: 0, totalUnits: totalBytes, completedFiles: 0, totalFiles: packages.count,
                bytesPerSecond: 0, currentFile: packages.first?.fileName ?? ""
            ),
            "Native download of \(packages.count) Steam packages…"
        )

        try await downloader.download(jobs: jobs) { progress in
            let detail = String(
                format: "Native CDN %.1f MB/s · %d/%d files · %@",
                progress.bytesPerSecond / 1_000_000,
                progress.completedFiles,
                progress.totalFiles,
                progress.currentFile
            )
            onProgress?(progress, detail)
        }

        onProgress?(
            DownloadProgress(
                completedUnits: totalBytes, totalUnits: totalBytes,
                completedFiles: packages.count, totalFiles: packages.count,
                bytesPerSecond: 0, currentFile: "extract"
            ),
            "Extracting packages on macOS (no Wine)…"
        )

        for (index, pkg) in packages.enumerated() {
            let archive = packagesDir.appending(path: pkg.fileName)
            try await extractSteamZip(archive, to: extractDir)
            if index % 2 == 0 {
                onProgress?(
                    DownloadProgress(
                        completedUnits: totalBytes, totalUnits: totalBytes,
                        completedFiles: index + 1, totalFiles: packages.count,
                        bytesPerSecond: 0, currentFile: pkg.fileName
                    ),
                    "Extracting \(index + 1)/\(packages.count): \(pkg.name)"
                )
            }
        }

        let steamExe = extractDir.appending(path: "Steam.exe")
        let steamExeLower = extractDir.appending(path: "steam.exe")
        if FileManager.default.fileExists(atPath: steamExeLower.path),
           !FileManager.default.fileExists(atPath: steamExe.path) {
            try FileManager.default.copyItem(at: steamExeLower, to: steamExe)
        }
        guard FileManager.default.fileExists(atPath: steamExe.path)
                || FileManager.default.fileExists(atPath: steamExeLower.path) else {
            throw SteamClientSeederError.missingSteamExecutable
        }

        let bottleSteam = bottleURL
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
        try store.ensureDir(bottleSteam)

        onProgress?(
            DownloadProgress(
                completedUnits: totalBytes, totalUnits: totalBytes,
                completedFiles: packages.count, totalFiles: packages.count,
                bytesPerSecond: 0, currentFile: "materialize"
            ),
            "Materializing into bottle (APFS clone when possible)…"
        )

        try store.materializeTree(from: extractDir, to: bottleSteam)

        let bottlePackages = bottleSteam.appending(path: "package")
        try store.ensureDir(bottlePackages)
        for pkg in packages {
            let src = packagesDir.appending(path: pkg.fileName)
            let dst = bottlePackages.appending(path: pkg.fileName)
            try store.materialize(from: src, to: dst)
        }
        try store.materialize(
            from: packagesDir.appending(path: "steam_client_win32"),
            to: bottlePackages.appending(path: "steam_client_win32")
        )

        // Mark client as present so Steam prefers local packages.
        let stamp = bottleSteam.appending(path: ".macbottle_native_seed")
        try """
        version=\(version)
        packages=\(packages.count)
        seeded_at=\(ISO8601DateFormatter().string(from: Date()))
        """.write(to: stamp, atomically: true, encoding: .utf8)

        return SteamClientSeedResult(
            version: version,
            packageCount: packages.count,
            totalBytes: totalBytes,
            steamRoot: bottleSteam
        )
    }

    private struct ManifestFetch {
        let data: Data
        let packages: [SteamPackage]
        let version: String
        let text: String
    }

    private func fetchManifest() async throws -> ManifestFetch {
        let (data, response) = try await URLSession.shared.data(from: Self.manifestURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SteamClientSeederError.manifestUnavailable
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw SteamClientSeederError.manifestUnavailable
        }
        let root = try VDF.parse(text)
        let packages = VDF.collectPackages(from: root)
        let version = root["win32"]?["version"]?.stringValue
            ?? root.objectValue?.values.compactMap { $0["version"]?.stringValue }.first
            ?? "unknown"
        return ManifestFetch(data: data, packages: packages, version: version, text: text)
    }

    private func extractSteamZip(_ archive: URL, to destination: URL) async throws {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: archive)
        guard let zipSignature = data.range(of: Data([0x50, 0x4b, 0x03, 0x04])) else {
            return
        }

        let tempZip = fileManager.temporaryDirectory.appending(path: "macbottle-\(UUID().uuidString).zip")
        do {
            try data.write(to: tempZip)
            try await runUnzip(tempZip, destination: destination)
        } catch {
            let stripped = Data(data[zipSignature.lowerBound...])
            try stripped.write(to: tempZip)
            try await runUnzip(tempZip, destination: destination)
        }
        try? fileManager.removeItem(at: tempZip)
    }

    private func runUnzip(_ zipURL: URL, destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let result = try await ProcessRunner.run(
            path: "/usr/bin/unzip",
            arguments: ["-o", "-q", zipURL.path, "-d", destination.path]
        )
        if result.exitCode > 1 {
            throw SteamClientSeederError.unzipFailed(
                zipURL.lastPathComponent + " " + result.standardErrorString
            )
        }
    }
}
