//
//  WinePathTests.swift
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

final class WinePathTests: XCTestCase {
    private let bottle = URL(fileURLWithPath: "/tmp/bottles/demo", isDirectory: true)

    func testTranslatesDriveCFileIntoWindowsPath() {
        let file = bottle.appending(path: "drive_c/Games/Game/game.exe")
        XCTAssertEqual(
            WinePath.windowsPath(for: file, inBottle: bottle),
            "C:\\Games\\Game\\game.exe"
        )
    }

    func testDriveCRootMapsToBackslashRoot() {
        let root = bottle.appending(path: "drive_c")
        XCTAssertEqual(WinePath.windowsPath(for: root, inBottle: bottle), "C:\\")
    }

    func testNestedDriveCNameIsNotMistakenForTheBottle() {
        let file = URL(fileURLWithPath: "/tmp/bottles/demo-other/drive_c/game.exe")
        XCTAssertEqual(
            WinePath.windowsPath(for: file, inBottle: bottle),
            "\\tmp\\bottles\\demo-other\\drive_c\\game.exe"
        )
    }

    func testPathOutsideTheBottleKeepsItsShape() {
        let file = URL(fileURLWithPath: "/Users/me/Downloads/setup.exe")
        XCTAssertEqual(
            WinePath.windowsPath(for: file, inBottle: bottle),
            "\\Users\\me\\Downloads\\setup.exe"
        )
    }
}
