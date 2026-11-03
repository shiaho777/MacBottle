//
//  ShellArgumentParserTests.swift
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
@testable import MacBottleKit

final class ShellArgumentParserTests: XCTestCase {
    func testQuotedPathWithSpacesStaysOneArgument() {
        XCTAssertEqual(
            ShellArgumentParser.parse(#"--path "C:\My Game\game.exe" -windowed"#),
            ["--path", #"C:\My Game\game.exe"#, "-windowed"]
        )
    }

    func testWindowsBackslashesArePreserved() {
        XCTAssertEqual(
            ShellArgumentParser.parse(#"C:\Games\foo.exe --save-dir D:\Saves"#),
            [#"C:\Games\foo.exe"#, "--save-dir", #"D:\Saves"#]
        )
    }

    func testEscapedSpaceAndQuotes() {
        XCTAssertEqual(
            ShellArgumentParser.parse(#"a\ b "say \"hi\"" 'single quoted'"#),
            ["a b", #"say "hi""#, "single quoted"]
        )
    }

    func testEmptyInputAndUnterminatedQuote() {
        XCTAssertEqual(ShellArgumentParser.parse(""), [])
        XCTAssertEqual(ShellArgumentParser.parse(#""unterminated"#), ["unterminated"])
    }

    func testEmptyQuotedArgumentIsPreserved() {
        XCTAssertEqual(ShellArgumentParser.parse(#"a "" b"#), ["a", "", "b"])
    }
}
