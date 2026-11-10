//
//  NativeJavaTests.swift
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

import XCTest
@testable import MacBottleKit

final class NativeJavaTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "native-java-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeEmbeddedJarExe(prefixBytes: Int = 4096) throws -> URL {
        let payload = workDir.appending(path: "payload")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("hello from the jar".utf8).write(to: payload.appending(path: "hello.txt"))
        let jar = workDir.appending(path: "payload.jar")
        let zip = try ProcessRunner.runSync(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-r", jar.path(percentEncoded: false), "hello.txt"],
            currentDirectory: payload
        )
        XCTAssertEqual(zip.exitCode, 0)

        var exe = Data(repeating: 0x90, count: prefixBytes)
        exe.append(try Data(contentsOf: jar))
        let url = workDir.appending(path: "Launcher.exe")
        try exe.write(to: url)
        return url
    }

    func testFindsAndExtractsEmbeddedJar() throws {
        let exe = try makeEmbeddedJarExe()
        XCTAssertTrue(EmbeddedJarExtractor.hasEmbeddedJar(at: exe))

        let destination = workDir.appending(path: "extracted.jar")
        try EmbeddedJarExtractor.extractJar(from: exe, to: destination)
        let listing = try ProcessRunner.runSync(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-l", destination.path(percentEncoded: false)]
        )
        XCTAssertEqual(listing.exitCode, 0)
        XCTAssertTrue(listing.standardOutputString.contains("hello.txt"))
    }

    func testPlainExecutableHasNoEmbeddedJar() throws {
        let url = workDir.appending(path: "Game.exe")
        try Data(repeating: 0x4D, count: 2048).write(to: url)
        XCTAssertFalse(EmbeddedJarExtractor.hasEmbeddedJar(at: url))
        XCTAssertThrowsError(try EmbeddedJarExtractor.extractJar(from: url, to: workDir.appending(path: "x.jar")))
    }

    func testDiscoversJdksAndPrefersTheNewest() throws {
        let root = workDir.appending(path: "JavaVirtualMachines")
        try makeFakeJDK(named: "temurin-17.jdk", version: "17.0.2")
        try makeFakeJDK(named: "corretto-21.jdk", version: "21.0.9")

        let runtimes = MacJavaRuntimeLocator.runtimes(
            environment: [:],
            searchRoots: [root]
        )
        XCTAssertEqual(runtimes.map(\.version), ["21.0.9", "17.0.2"])
        XCTAssertEqual(
            MacJavaRuntimeLocator.preferred(environment: [:], searchRoots: [root])?.version,
            "21.0.9"
        )
    }

    func testVersionRankHandlesLegacyOneDotEight() {
        XCTAssertGreaterThan(
            MacJavaRuntimeLocator.versionRank("21.0.9"),
            MacJavaRuntimeLocator.versionRank("1.8.0_442")
        )
        XCTAssertGreaterThan(
            MacJavaRuntimeLocator.versionRank("17.0.2"),
            MacJavaRuntimeLocator.versionRank("11.0.20")
        )
    }

    func testLauncherRunsJavaWithJarAndLogsOutput() throws {
        let home = try makeFakeJDK(named: "fake.jdk", version: "21.0.9")
        let runtime = MacJavaRuntime(home: home, version: "21.0.9")
        let jar = workDir.appending(path: "app.jar")
        try Data().write(to: jar)

        let launch = try NativeJavaLauncher.launch(
            jar: jar,
            runtime: runtime,
            workingDirectory: workDir,
            bundleID: "app.macbottle.tests"
        )
        launch.process.waitUntilExit()
        XCTAssertEqual(launch.process.terminationStatus, 0)

        let log = try String(contentsOf: launch.logFile, encoding: .utf8)
        XCTAssertTrue(log.contains("-jar"))
        XCTAssertTrue(log.contains(jar.lastPathComponent))
        try? FileManager.default.removeItem(at: NativeJavaLauncher.logDirectory(bundleID: "app.macbottle.tests"))
    }

    private func makeFakeJDK(named name: String, version: String) throws -> URL {
        let home = workDir
            .appending(path: "JavaVirtualMachines")
            .appending(path: name)
            .appending(path: "Contents")
            .appending(path: "Home")
        try FileManager.default.createDirectory(
            at: home.appending(path: "bin"),
            withIntermediateDirectories: true
        )
        try "JAVA_VERSION=\"\(version)\"\n".write(
            to: home.appending(path: "release"),
            atomically: true,
            encoding: .utf8
        )
        let java = home.appending(path: "bin/java")
        try "#!/bin/sh\necho \"$@\"\n".write(to: java, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        return home
    }
}
