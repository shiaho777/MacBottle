//
//  NativeJavaLauncher.swift
//  MacBottleKit
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

import CryptoKit
import Foundation

public struct NativeJavaLaunch {
    public let jar: URL
    public let logFile: URL
    public let process: Process
}

public enum NativeJavaLauncher {
    public static func cacheDirectory(bundleID: String = Bundle.macBottleBundleIdentifier) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID)
            .appending(path: "NativeJava", directoryHint: .isDirectory)
    }

    public static func logDirectory(bundleID: String = Bundle.macBottleBundleIdentifier) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs")
            .appending(path: bundleID)
            .appending(path: "NativeJava", directoryHint: .isDirectory)
    }

    /// Extract the launcher's embedded JAR to a cache location. Reuses
    /// the previous extraction while the executable is unchanged.
    public static func prepareJar(
        from executable: URL,
        bundleID: String = Bundle.macBottleBundleIdentifier
    ) throws -> URL {
        let directory = cacheDirectory(bundleID: bundleID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let digest = SHA256.hash(data: Data(executable.path(percentEncoded: false).utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        let base = executable.deletingPathExtension().lastPathComponent
        let destination = directory.appending(path: "\(base)-\(digest).jar")

        let fileManager = FileManager.default
        let sourceDate = (try? fileManager.attributesOfItem(
            atPath: executable.path(percentEncoded: false)
        )[.modificationDate]) as? Date
        let cachedDate = (try? fileManager.attributesOfItem(
            atPath: destination.path(percentEncoded: false)
        )[.modificationDate]) as? Date
        if let sourceDate, let cachedDate, cachedDate >= sourceDate {
            return destination
        }
        return try EmbeddedJarExtractor.extractJar(from: executable, to: destination)
    }

    public static func launch(
        jar: URL,
        runtime: MacJavaRuntime,
        workingDirectory: URL? = nil,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        bundleID: String = Bundle.macBottleBundleIdentifier
    ) throws -> NativeJavaLaunch {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let logFile = logDirectory(bundleID: bundleID)
            .appending(path: "\(formatter.string(from: Date()))-\(jar.deletingPathExtension().lastPathComponent).log")

        let process = try ProcessRunner.launch(
            executable: runtime.javaBinary,
            arguments: ["-jar", jar.path(percentEncoded: false)] + arguments,
            currentDirectory: workingDirectory,
            environment: environment,
            qualityOfService: .userInitiated,
            outputFile: logFile
        )
        return NativeJavaLaunch(jar: jar, logFile: logFile, process: process)
    }
}
