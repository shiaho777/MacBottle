//
//  VDF.swift
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

public enum VDFNode: Sendable, Equatable {
    case value(String)
    case object([String: VDFNode])

    public subscript(key: String) -> VDFNode? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    public var stringValue: String? {
        if case .value(let s) = self { return s }
        return nil
    }

    public var objectValue: [String: VDFNode]? {
        if case .object(let d) = self { return d }
        return nil
    }
}

public enum VDF {
    public static func parse(_ text: String) throws -> VDFNode {
        var lexer = Lexer(text)
        let rootKey = try lexer.string()
        let rootValue = try parseValue(&lexer)
        return .object([rootKey: rootValue])
    }

    private static func parseValue(_ lexer: inout Lexer) throws -> VDFNode {
        if lexer.peekIsBrace() {
            return try parseObject(&lexer)
        }
        return .value(try lexer.string())
    }

    private static func parseObject(_ lexer: inout Lexer) throws -> VDFNode {
        try lexer.expectBraceOpen()
        var dict: [String: VDFNode] = [:]
        while !lexer.peekIsBraceClose() {
            let key = try lexer.string()
            let value = try parseValue(&lexer)
            dict[key] = value
        }
        try lexer.expectBraceClose()
        return .object(dict)
    }

    public static func collectPackages(from root: VDFNode) -> [SteamPackage] {
        var results: [SteamPackage] = []
        walk(root, path: [], into: &results)
        var seen = Set<String>()
        return results.filter { seen.insert($0.fileName).inserted }
    }

    private static func walk(_ node: VDFNode, path: [String], into results: inout [SteamPackage]) {
        guard case .object(let dict) = node else { return }
        if let file = dict["file"]?.stringValue {
            let size = Int64(dict["size"]?.stringValue ?? "") ?? 0
            let sha2 = dict["sha2"]?.stringValue
            let zipvz = dict["zipvz"]?.stringValue
            let isBootstrap = dict["IsBootstrapperPackage"]?.stringValue == "1"
            results.append(
                SteamPackage(
                    name: path.last ?? file,
                    fileName: file,
                    size: size,
                    sha2: sha2,
                    zipvzFileName: zipvz,
                    isBootstrapper: isBootstrap
                )
            )
        }
        for (key, child) in dict {
            if case .object = child {
                walk(child, path: path + [key], into: &results)
            }
        }
    }
}

private struct Lexer {
    private let scalars: [Character]
    private var index: Int = 0

    init(_ text: String) {
        self.scalars = Array(text)
    }

    mutating func string() throws -> String {
        skipWhitespaceAndComments()
        guard current() == "\"" else {
            throw VDFError.expectedString
        }
        advance()
        var out = ""
        while let ch = current(), ch != "\"" {
            if ch == "\\" {
                advance()
                if let escaped = current() {
                    out.append(escaped)
                    advance()
                }
            } else {
                out.append(ch)
                advance()
            }
        }
        guard current() == "\"" else { throw VDFError.unterminatedString }
        advance()
        return out
    }

    mutating func expectBraceOpen() throws {
        skipWhitespaceAndComments()
        guard current() == "{" else { throw VDFError.expectedBrace }
        advance()
    }

    mutating func expectBraceClose() throws {
        skipWhitespaceAndComments()
        guard current() == "}" else { throw VDFError.expectedBrace }
        advance()
    }

    mutating func peekIsBrace() -> Bool {
        let saved = index
        skipWhitespaceAndComments()
        let isBrace = current() == "{"
        index = saved
        return isBrace
    }

    mutating func peekIsBraceClose() -> Bool {
        let saved = index
        skipWhitespaceAndComments()
        let isBrace = current() == "}"
        index = saved
        return isBrace
    }

    private mutating func skipWhitespaceAndComments() {
        while let ch = current() {
            if ch.isWhitespace {
                advance()
                continue
            }
            if ch == "/" && peekNext() == "/" {
                advance(); advance()
                while let c = current(), c != "\n" { advance() }
                continue
            }
            break
        }
    }

    private func current() -> Character? {
        guard index < scalars.count else { return nil }
        return scalars[index]
    }

    private func peekNext() -> Character? {
        let next = index + 1
        guard next < scalars.count else { return nil }
        return scalars[next]
    }

    private mutating func advance() {
        index += 1
    }
}

public enum VDFError: Error {
    case expectedString
    case unterminatedString
    case expectedBrace
}

public struct SteamPackage: Sendable, Hashable, Identifiable {
    public var id: String { fileName }
    public let name: String
    public let fileName: String
    public let size: Int64
    public let sha2: String?
    public let zipvzFileName: String?
    public let isBootstrapper: Bool

    public var preferredRemoteName: String { fileName }
}
