//
//  ShellArgumentParser.swift
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

/// Splits a user-entered argument string into argv without invoking a
/// shell. The previous `split(whereSeparator: \.isWhitespace)` broke every
/// quoted path (`--path "C:\My Game"` became three arguments).
///
/// Backslash is deliberately *not* a general escape character: Windows
/// paths are full of them. It only escapes whitespace, quotes, and
/// another backslash, which is the minimum needed to describe argv while
/// keeping `C:\Games\foo.exe` intact.
public enum ShellArgumentParser {
    public static func parse(_ input: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var hasToken = false
        var quote: Character?
        var iterator = input.makeIterator()

        func flush() {
            guard hasToken else { return }
            arguments.append(current)
            current = ""
            hasToken = false
        }

        while let character = iterator.next() {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\" {
                    guard let next = iterator.next() else {
                        current.append(character)
                        break
                    }
                    if next == activeQuote || next == "\\" {
                        current.append(next)
                    } else {
                        current.append(character)
                        current.append(next)
                    }
                } else {
                    current.append(character)
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                hasToken = true
            case "\\":
                guard let next = iterator.next() else {
                    current.append(character)
                    hasToken = true
                    break
                }
                if next.isWhitespace || next == "\"" || next == "'" || next == "\\" {
                    current.append(next)
                } else {
                    current.append(character)
                    current.append(next)
                }
                hasToken = true
            case _ where character.isWhitespace:
                flush()
            default:
                current.append(character)
                hasToken = true
            }
        }

        flush()
        return arguments
    }
}
