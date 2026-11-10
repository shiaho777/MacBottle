//
//  MacJavaRuntime.swift
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

import Foundation

public struct MacJavaRuntime: Sendable, Equatable, Identifiable {
    public let home: URL
    public let version: String

    public var id: String { home.path(percentEncoded: false) }

    public var javaBinary: URL {
        home.appending(path: "bin").appending(path: "java")
    }

    public var isUsable: Bool {
        FileManager.default.isExecutableFile(atPath: javaBinary.path(percentEncoded: false))
    }

    public init(home: URL, version: String) {
        self.home = home
        self.version = version
    }
}

public enum MacJavaRuntimeLocator {
    /// A Mac JDK runs the launcher's embedded JAR without Rosetta, which
    /// is the whole point: the JVM's JIT output is native arm64 code.
    public static func runtimes(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        extraRoots: [URL] = [],
        searchRoots: [URL]? = nil
    ) -> [MacJavaRuntime] {
        let fileManager = FileManager.default
        var homes: [URL] = []

        if let javaHome = environment["JAVA_HOME"], !javaHome.isEmpty {
            homes.append(URL(fileURLWithPath: javaHome, isDirectory: true))
        }

        let roots = searchRoots ?? (extraRoots + [
            URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library/Java/JavaVirtualMachines", directoryHint: .isDirectory)
        ])
        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                if entry.lastPathComponent.hasSuffix(".jdk") || entry.lastPathComponent.hasSuffix(".jre") {
                    homes.append(entry.appending(path: "Contents").appending(path: "Home"))
                } else {
                    homes.append(entry)
                }
            }
        }

        var seen = Set<String>()
        let runtimes = homes.compactMap { home -> MacJavaRuntime? in
            let resolved = home.resolvingSymlinksInPath()
            let key = resolved.path(percentEncoded: false)
            guard seen.insert(key).inserted else { return nil }
            guard let version = version(at: resolved) else { return nil }
            let runtime = MacJavaRuntime(home: resolved, version: version)
            return runtime.isUsable ? runtime : nil
        }
        return runtimes.sorted { versionRank($0.version) > versionRank($1.version) }
    }

    public static func preferred(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        extraRoots: [URL] = [],
        searchRoots: [URL]? = nil
    ) -> MacJavaRuntime? {
        runtimes(
            environment: environment,
            extraRoots: extraRoots,
            searchRoots: searchRoots
        ).first
    }

    static func version(at home: URL) -> String? {
        let release = home.appending(path: "release")
        if let text = try? String(contentsOf: release, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("JAVA_VERSION=") {
                let raw = line.dropFirst("JAVA_VERSION=".count)
                let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// "21.0.9" → 21_000_009, "1.8.0_442" → 8_000_442. Good enough to
    /// order installed JDKs; not a full semver parser.
    static func versionRank(_ version: String) -> Int {
        var parts = version
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        if parts.count >= 2, parts[0] == 1, parts[1] > 1 {
            parts.removeFirst()
        }
        while parts.count < 3 { parts.append(0) }
        return parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2]
    }
}
