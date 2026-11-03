//
//  WineRegistryFile.swift
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

public enum WineRegistryFile {
    public static func userRegistryURL(for bottle: Bottle) -> URL {
        bottle.url.appending(path: "user.reg")
    }

    @discardableResult
    public static func setStringValue(
        bottle: Bottle,
        keyPath: String,
        name: String,
        value: String
    ) throws -> Bool {
        try mutate(bottle: bottle) { text in
            upsert(
                in: &text,
                keyPath: keyPath,
                name: name,
                line: "\"\(name)\"=\"\(escapeString(value))\""
            )
        }
    }

    @discardableResult
    public static func setDwordValue(
        bottle: Bottle,
        keyPath: String,
        name: String,
        value: Int
    ) throws -> Bool {
        let hex = String(format: "%08x", UInt32(truncatingIfNeeded: value))
        return try mutate(bottle: bottle) { text in
            upsert(
                in: &text,
                keyPath: keyPath,
                name: name,
                line: "\"\(name)\"=dword:\(hex)"
            )
        }
    }

    public static func stringValue(
        bottle: Bottle,
        keyPath: String,
        name: String
    ) -> String? {
        guard let text = try? String(contentsOf: userRegistryURL(for: bottle), encoding: .utf8) else {
            return nil
        }
        guard let body = sectionBody(in: text, keyPath: keyPath) else { return nil }
        let pattern = #"^\"\#(NSRegularExpression.escapedPattern(for: name))\"=\"(.*)\"$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return nil
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: body) else {
            return nil
        }
        return unescapeString(String(body[valueRange]))
    }

    public static func dwordValue(
        bottle: Bottle,
        keyPath: String,
        name: String
    ) -> Int? {
        guard let text = try? String(contentsOf: userRegistryURL(for: bottle), encoding: .utf8) else {
            return nil
        }
        guard let body = sectionBody(in: text, keyPath: keyPath) else { return nil }
        let pattern = #"^\"\#(NSRegularExpression.escapedPattern(for: name))\"=dword:([0-9a-fA-F]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return nil
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: body) else {
            return nil
        }
        return Int(String(body[valueRange]), radix: 16)
    }

    private static func mutate(bottle: Bottle, _ body: (inout String) -> Bool) throws -> Bool {
        let url = userRegistryURL(for: bottle)
        var text = try String(contentsOf: url, encoding: .utf8)
        let changed = body(&text)
        if changed {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return changed
    }

    private static func upsert(
        in text: inout String,
        keyPath: String,
        name: String,
        line: String
    ) -> Bool {
        let header = "[\(keyPath)]"
        if let sectionRange = findSectionRange(in: text, header: header) {
            var section = String(text[sectionRange])
            let namePattern = #"^\"\#(NSRegularExpression.escapedPattern(for: name))\"=.*$"#
            if let regex = try? NSRegularExpression(pattern: namePattern, options: .anchorsMatchLines) {
                let nsRange = NSRange(section.startIndex..<section.endIndex, in: section)
                if let match = regex.firstMatch(in: section, options: [], range: nsRange),
                   let matchRange = Range(match.range, in: section) {
                    let existing = String(section[matchRange])
                    if existing == line {
                        return false
                    }
                    section.replaceSubrange(matchRange, with: line)
                    text.replaceSubrange(sectionRange, with: section)
                    return true
                }
            }
            if !section.hasSuffix("\n") {
                section.append("\n")
            }
            section.append(line)
            section.append("\n")
            text.replaceSubrange(sectionRange, with: section)
            return true
        }

        let stamp = Int(Date().timeIntervalSince1970)
        var addition = "\n\(header) \(stamp)\n"
        addition += "#time=\(String(format: "%x", stamp))\n"
        addition += "\(line)\n"
        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        text.append(addition)
        return true
    }

    private static func findSectionRange(in text: String, header: String) -> Range<String.Index>? {
        guard let headerRange = text.range(of: header) else { return nil }
        let afterHeader = headerRange.upperBound
        let search = text[afterHeader...]
        if let next = search.range(of: "\n[", options: []) {
            return headerRange.lowerBound..<next.lowerBound
        }
        return headerRange.lowerBound..<text.endIndex
    }

    private static func sectionBody(in text: String, keyPath: String) -> String? {
        let header = "[\(keyPath)]"
        guard let range = findSectionRange(in: text, header: header) else { return nil }
        return String(text[range])
    }

    private static func escapeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unescapeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
