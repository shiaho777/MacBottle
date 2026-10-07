//
//  URL+Extensions.swift
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

extension String {
    public var esc: String {
        let esc = ["\\", "\"", "'", " ", "(", ")", "[", "]", "{", "}", "&", "|",
                   ";", "<", ">", "`", "$", "!", "*", "?", "#", "~", "="]
        var str = self
        for char in esc {
            str = str.replacingOccurrences(of: char, with: "\\" + char)
        }
        return str
    }

    /// POSIX single-quoted form. Safe against metacharacter injection
    /// regardless of the content.
    public var posixQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Split a launch string the way a program argument list is typed.
    ///
    /// Whitespace separates tokens. Double quotes group a token, including
    /// spaces. Inside quotes, `\"` and `\\` decode to a quote and a
    /// backslash. A backslash anywhere else stays a backslash, because
    /// Windows paths use it as a separator.
    public func commandLineTokens() -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var started = false
        let chars = Array(self)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if inQuotes {
                if character == "\\" {
                    let nextIndex = index + 1
                    if nextIndex < chars.count {
                        let next = chars[nextIndex]
                        if next == "\"" || next == "\\" {
                            current.append(next)
                            index += 2
                            started = true
                            continue
                        }
                    }
                    current.append(character)
                    index += 1
                    started = true
                    continue
                }
                if character == "\"" {
                    inQuotes = false
                    started = true
                    index += 1
                    continue
                }
                current.append(character)
                started = true
                index += 1
                continue
            }
            if character == "\"" {
                inQuotes = true
                started = true
                index += 1
                continue
            }
            if character.isWhitespace {
                if started {
                    tokens.append(current)
                    current = ""
                    started = false
                }
                index += 1
                continue
            }
            current.append(character)
            started = true
            index += 1
        }
        if started {
            tokens.append(current)
        }
        return tokens
    }
}

extension URL {
    public var esc: String {
        path.esc
    }

    public func prettyPath() -> String {
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: Bundle.main.bundleIdentifier ?? Bundle.whiskyBundleIdentifier, with: "Whisky")
            .replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
        return prettyPath
    }

    // NOT to be used for logic only as UI decoration
    public func prettyPath(_ bottle: Bottle) -> String {
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: bottle.url.path(percentEncoded: false), with: "")
            .replacingOccurrences(of: "/drive_c/", with: "C:\\")
            .replacingOccurrences(of: "/", with: "\\")
        return prettyPath
    }

    // There is probably a better way to do this
    public func updateParentBottle(old: URL, new: URL) -> URL {
        let originalPath = path(percentEncoded: false)

        var oldBottlePath = old.path(percentEncoded: false)
        if oldBottlePath.last != "/" {
            oldBottlePath += "/"
        }

        var newBottlePath = new.path(percentEncoded: false)
        if newBottlePath.last != "/" {
            newBottlePath += "/"
        }

        let newPath = originalPath.replacingOccurrences(of: oldBottlePath,
                                                        with: newBottlePath)
        return URL(filePath: newPath)
    }
}

extension URL: @retroactive Identifiable {
    public var id: URL { self }
}
