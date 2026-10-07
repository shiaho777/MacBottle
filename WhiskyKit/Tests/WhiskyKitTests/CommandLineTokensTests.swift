//
//  CommandLineTokensTests.swift
//  WhiskyKitTests
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

final class CommandLineTokensTests: XCTestCase {
    func testUnquotedWhitespaceSplitsAndCollapses() {
        XCTAssertEqual(
            "  -windowed   -foo ".commandLineTokens(),
            ["-windowed", "-foo"]
        )
        XCTAssertEqual("".commandLineTokens(), [])
        XCTAssertEqual("   ".commandLineTokens(), [])
    }

    func testQuotedPathStaysOneArgument() {
        XCTAssertEqual(
            #"-jar "C:\Games\My Pack\minecraft.jar""#.commandLineTokens(),
            ["-jar", #"C:\Games\My Pack\minecraft.jar"#]
        )
    }

    func testEscapesInsideQuotes() {
        XCTAssertEqual(
            #""say \"hello\\world\"""#.commandLineTokens(),
            [#"say "hello\world""#]
        )
    }

    func testBackslashOutsideQuotesIsLiteral() {
        XCTAssertEqual(
            #"C:\Program Files\game.exe"#.commandLineTokens(),
            [#"C:\Program"#, #"Files\game.exe"#]
        )
    }

    func testEmptyQuotedTokenIsPreserved() {
        XCTAssertEqual(#"prog """#.commandLineTokens(), ["prog", ""])
    }

    func testTerminalCommandQuotesTheRejoinedPath() {
        let bottle = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/macbottle-args-\(UUID().uuidString)"),
            inFlight: true
        )
        let command = Wine.generateRunCommand(
            at: URL(fileURLWithPath: "/tmp/game.exe"),
            bottle: bottle,
            args: #"-jar "C:\Games\My Pack\minecraft.jar""#,
            environment: [:]
        )
        XCTAssertTrue(command.contains(#"'C:\Games\My Pack\minecraft.jar'"#))
        XCTAssertFalse(command.contains(#"'C:\Games\My'"#))
    }
}
