//
//  RendererEnvironmentTests.swift
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

final class RendererEnvironmentTests: XCTestCase {
    func testMoltenVKDefaultsAndVulkanOverride() {
        var env: [String: String] = [:]
        RendererEnvironment.applyMoltenVK(to: &env)
        XCTAssertEqual(env["MVK_CONFIG_LOG_LEVEL"], "1")
        XCTAssertEqual(env["MVK_CONFIG_PREALLOCATE_SWAPCHAIN_IMAGES"], "1")
        XCTAssertEqual(env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"], "0")
        XCTAssertEqual(env["MVK_CONFIG_RESUME_LOST_DEVICE"], "1")
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "vulkan-1=b")
    }

    func testVulkanOverrideReplacesStaleEntry() {
        var env = ["WINEDLLOVERRIDES": "dxgi,d3d9,d3d10core,d3d11=n,b;vulkan-1=n,b"]
        RendererEnvironment.applyMoltenVK(to: &env)
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertTrue(overrides.contains("dxgi,d3d9,d3d10core,d3d11=n,b"))
        XCTAssertTrue(overrides.contains("vulkan-1=b"))
        XCTAssertFalse(overrides.contains("vulkan-1=n,b"))
        XCTAssertEqual(overrides.components(separatedBy: "vulkan-1=").count, 2)
    }

    func testDXMTUsesNativeD3D11AndLeavesDXVK() {
        var env = [
            "DXVK_HUD": "fps",
            "DXVK_CONFIG_FILE": "/tmp/game.conf",
            "WINEDLLOVERRIDES": "dxgi=n,b"
        ]
        RendererEnvironment.applyDXMT(to: &env)
        XCTAssertNil(env["DXVK_HUD"])
        XCTAssertNil(env["DXVK_CONFIG_FILE"])
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertTrue(overrides.contains("d3d11=n,b"))
        XCTAssertEqual(overrides.components(separatedBy: "dxgi=n,b").count, 2)
    }

    func testVKD3DUsesNativeD3D12() {
        var env: [String: String] = [:]
        RendererEnvironment.applyVKD3D(to: &env)
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertTrue(overrides.contains("d3d12=n,b"))
        XCTAssertTrue(overrides.contains("dxgi=n,b"))
    }

    func testWineD3DRemovesDXVKState() {        var env = [
            "DXVK_HUD": "fps",
            "DXVK_ASYNC": "1",
            "DXVK_CONFIG_FILE": "/tmp/game.conf",
            "WINEDLLOVERRIDES": "dxgi,d3d9=n,b"
        ]
        RendererEnvironment.applyWineD3D(to: &env)
        XCTAssertNil(env["DXVK_HUD"])
        XCTAssertNil(env["DXVK_ASYNC"])
        XCTAssertNil(env["DXVK_CONFIG_FILE"])
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertTrue(overrides.contains("dxgi=b"))
        XCTAssertTrue(overrides.contains("d3d9=b"))
        XCTAssertTrue(overrides.contains("d3d11=b"))
    }

    func testICDManifestIsFoundWhenPresent() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "renderer-env-\(UUID().uuidString)")
        let manifest = root.appending(path: "Wine/lib/external/MoltenVK_icd.json")
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: manifest)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = LocalPathEngine(
            identifier: "test",
            displayName: "Test",
            libraryRoot: root
        )
        XCTAssertEqual(RendererEnvironment.moltenVKICDManifest(in: engine), manifest)

        var env: [String: String] = [:]
        RendererEnvironment.applyMoltenVK(to: &env, engine: engine)
        XCTAssertEqual(env["VK_ICD_FILENAMES"], manifest.path(percentEncoded: false))
    }
}
