//
//  VDFTests.swift
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
@testable import WhiskyKit

final class VDFTests: XCTestCase {
    func testParsesManifestShape() throws {
        let text = """
        "AppState"
        {
            "appid" "123"
            "StateFlags" "4"
            "InstalledDepots"
            {
                "456"
                {
                    "manifest" "789"
                }
            }
        }
        """
        let root = try VDF.parse(text)
        XCTAssertEqual(root["AppState"]?["appid"]?.stringValue, "123")
        XCTAssertEqual(
            root["AppState"]?["InstalledDepots"]?["456"]?["manifest"]?.stringValue,
            "789"
        )
    }

    func testDeeplyNestedObjectIsRejected() {
        var text = "\"root\" {"
        for index in 0..<100 {
            text += "\"k\(index)\" {"
        }
        text += "\"value\" \"x\""
        for _ in 0..<101 {
            text += "}"
        }
        XCTAssertThrowsError(try VDF.parse(text)) { error in
            guard case VDFError.depthExceeded = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
