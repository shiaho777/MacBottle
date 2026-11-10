//
//  EmbeddedJarExtractor.swift
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

import Foundation

public enum EmbeddedJarError: Error, LocalizedError, Equatable {
    case noEmbeddedJar
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .noEmbeddedJar:
            return "This executable does not contain an embedded JAR."
        case .unreadable:
            return "The executable could not be read."
        }
    }
}

/// launch4j and its relatives append a complete JAR to the EXE. The PE
/// import table never mentions `jvm.dll` (the wrapper loads it at
/// runtime), which is why a Java launcher like HMCL looks like a
/// non-Java game to name/import heuristics.
///
/// The JAR is a normal ZIP payload whose end-of-central-directory record
/// still sits at the end of the file. That gives an exact start offset
/// without guessing where the PE image ends.
public enum EmbeddedJarExtractor {
    private static let localHeader = Data([0x50, 0x4B, 0x03, 0x04]) // PK\x03\x04
    private static let centralHeader = Data([0x50, 0x4B, 0x01, 0x02]) // PK\x01\x02
    private static let endOfCentral = Data([0x50, 0x4B, 0x05, 0x06]) // PK\x05\x06

    /// Byte range of the embedded JAR inside `url`, if any.
    public static func embeddedJarRange(at url: URL) throws -> Range<Int>? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw EmbeddedJarError.unreadable
        }
        guard data.count > 22 else { return nil }

        // The comment field can be up to 64 KB, so the EOCD may start
        // earlier than "last 22 bytes".
        let searchStart = max(0, data.count - 65_557)
        guard let eocd = data.range(
            of: endOfCentral,
            options: .backwards,
            in: searchStart..<data.count
        ) else {
            return nil
        }
        let eocdOffset = eocd.lowerBound
        guard eocdOffset + 22 <= data.count else { return nil }

        let centralSize = Int(data.uint32LE(at: eocdOffset + 12))
        let centralOffset = Int(data.uint32LE(at: eocdOffset + 16))
        guard centralSize > 0, centralOffset > 0 else { return nil }

        // centralDirectory = jarStart + centralOffset and must end at the EOCD.
        let jarStart = eocdOffset - centralSize - centralOffset
        guard jarStart >= 0,
              jarStart < eocdOffset,
              data.matches(localHeader, at: jarStart),
              data.matches(centralHeader, at: jarStart + centralOffset) else {
            return nil
        }
        return jarStart..<data.count
    }

    public static func hasEmbeddedJar(at url: URL) -> Bool {
        (try? embeddedJarRange(at: url)) != nil
    }

    @discardableResult
    public static func extractJar(from executable: URL, to destination: URL) throws -> URL {
        guard let range = try embeddedJarRange(at: executable) else {
            throw EmbeddedJarError.noEmbeddedJar
        }
        guard let data = try? Data(contentsOf: executable, options: .mappedIfSafe) else {
            throw EmbeddedJarError.unreadable
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.subdata(in: range).write(to: destination, options: .atomic)
        return destination
    }
}

private extension Data {
    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.baseAddress?.advanced(by: offset) else { return 0 }
            return base.loadUnaligned(as: UInt32.self).littleEndian
        }
    }

    func matches(_ signature: Data, at offset: Int) -> Bool {
        guard offset >= 0, offset + signature.count <= count else { return false }
        return self[offset..<(offset + signature.count)].elementsEqual(signature)
    }
}
