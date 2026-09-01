//
//  EngineImportServiceTests.swift
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

import XCTest
import SemanticVersion
@testable import WhiskyKit

final class EngineImportServiceTests: XCTestCase {
    private var workDir: URL!
    private var sourceRoot: URL!
    private var destination: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(component: "engine-import-\(UUID().uuidString)")
        sourceRoot = workDir.appending(component: "source")
        destination = workDir
            .appending(component: "Engines")
            .appending(component: "upstream-arm64")
        try? FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeWineTree(
        in root: URL,
        architectures: [WineArchitecture],
        binaryName: String = "wine",
        withVersionPlist: Bool = false
    ) throws {
        let binDir = root.appending(path: "Wine").appending(path: "bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let binary = binDir.appending(path: binaryName)
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        for architecture in architectures {
            let unixDir = root
                .appending(path: "Wine")
                .appending(path: "lib")
                .appending(path: "wine")
                .appending(path: architecture.unixDirectoryName)
            try FileManager.default.createDirectory(at: unixDir, withIntermediateDirectories: true)
            try Data("stub".utf8).write(to: unixDir.appending(path: "d3d11.so"))
        }
        if withVersionPlist {
            let version = WhiskyWineVersion(version: SemanticVersion(9, 9, 9))
            try PropertyListEncoder().encode(version).write(
                to: root.appending(path: "WhiskyWineVersion.plist")
            )
        }
    }

    func testValidateAcceptsArm64Layout() throws {
        try makeWineTree(in: sourceRoot, architectures: [.aarch64])
        let architectures = try EngineImportService.validate(engineRoot: sourceRoot)
        XCTAssertEqual(architectures, [.aarch64])
    }

    func testValidateRejectsMissingBinary() throws {
        let binDir = sourceRoot.appending(path: "Wine").appending(path: "bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try EngineImportService.validate(engineRoot: sourceRoot))
    }

    func testValidateRejectsMissingUnixModules() throws {
        let binDir = sourceRoot.appending(path: "Wine").appending(path: "bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let binary = binDir.appending(path: "wine")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        XCTAssertThrowsError(try EngineImportService.validate(engineRoot: sourceRoot)) { error in
            XCTAssertTrue(error is EngineImportError)
        }
    }

    func testImportFolderCopiesAndGeneratesVersionPlist() async throws {
        try makeWineTree(in: sourceRoot, architectures: [.aarch64])
        try await EngineImportService.importFolder(
            at: sourceRoot,
            into: destination,
            fallbackVersion: SemanticVersion(7, 7, 7)
        )
        let engine = WineEngineCatalog.arm64Engine()
        let probe = LocalPathEngine(
            identifier: engine.identifier,
            displayName: engine.displayName,
            libraryRoot: destination
        )
        XCTAssertTrue(probe.isInstalled(), "imported engine must be installed")
        // No source plist -> fallback version written so isInstalled() passes.
        XCTAssertEqual(probe.installedVersion(), SemanticVersion(7, 7, 7))
        XCTAssertTrue(WineArchitecture.available(in: destination).contains(.aarch64))
    }

    func testImportFolderPreservesSourcePlist() async throws {
        try makeWineTree(in: sourceRoot, architectures: [.aarch64], withVersionPlist: true)
        try await EngineImportService.importFolder(
            at: sourceRoot,
            into: destination,
            fallbackVersion: SemanticVersion(7, 7, 7)
        )
        let probe = LocalPathEngine(
            identifier: "upstream-arm64",
            displayName: "probe",
            libraryRoot: destination
        )
        XCTAssertEqual(probe.installedVersion(), SemanticVersion(9, 9, 9))
    }

    func testReimportReplacesDestinationAtomically() async throws {
        try makeWineTree(in: sourceRoot, architectures: [.aarch64])
        try await EngineImportService.importFolder(
            at: sourceRoot,
            into: destination,
            fallbackVersion: SemanticVersion(1, 0, 0)
        )
        // A second import (fresh source) must succeed, replacing the old install.
        let second = workDir.appending(component: "source2")
        try makeWineTree(in: second, architectures: [.aarch64, .x8664])
        try await EngineImportService.importFolder(
            at: second,
            into: destination,
            fallbackVersion: SemanticVersion(2, 0, 0)
        )
        XCTAssertTrue(WineArchitecture.available(in: destination).contains(.x8664))
    }

    func testCatalogExposesArm64Engine() {
        XCTAssertTrue(WineEngineCatalog.allEngines().contains { $0.identifier == "upstream-arm64" })
        XCTAssertNotNil(WineEngineCatalog.engine(id: WineEngineCatalog.arm64Identifier))
        XCTAssertEqual(WineEngineCatalog.arm64Engine().libraryRoot, WineEngineCatalog.arm64LibraryRoot)
    }
}
