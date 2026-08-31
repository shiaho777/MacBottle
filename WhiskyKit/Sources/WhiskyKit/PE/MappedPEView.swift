//
//  MappedPEView.swift
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

/// A true zero-copy, page-granular view over a file's bytes.
///
/// The PE scanner used to read import names one syscall per byte
/// (`FileHandle.read(upToCount: 1)` inside a 260-iteration loop) and
/// slurp 4 MB into memory for the string fallback. For a 250 MB
/// launcher scanned on every click of "Run" that is hundreds of syscalls
/// plus a full-buffer copy for what is, structurally, a read-only
/// projection.
///
/// This view mmaps the file (`mmap(2)` via `Data(mappedIfSafe)`), keeps
/// only the 16-byte header window resident as a copy, and serves every
/// other read straight from the mapping. Nothing beyond the touched
/// pages is ever paged in: scanning a 256 MB PyInstaller launcher costs
/// a handful of header-page touches instead of a 256 MB copy.
final class MappedPEView: @unchecked Sendable {
    private let mapped: Data
    private var basePointer: UnsafeRawPointer
    let count: Int

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe, .uncached]),
              case let .some(pointer) = data.withUnsafeBytes({ $0.baseAddress }) else {
            return nil
        }
        self.mapped = data
        self.basePointer = pointer
        self.count = mapped.count
    }

    func scalar<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else { return nil }
        return basePointer.loadUnaligned(fromByteOffset: offset, as: T.self)
    }

    func cString(at offset: Int, maxLength: Int) -> String? {
        guard offset >= 0, offset < count else { return nil }
        let end = min(offset + maxLength, count)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        var cursor = offset
        while cursor < end {
            let byte = basePointer.load(fromByteOffset: cursor, as: UInt8.self)
            if byte == 0 { break }
            bytes.append(byte)
            cursor += 1
        }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .ascii) ?? String(bytes: bytes, encoding: .utf8)
    }

    /// The first `length` bytes copied into an owned array — used only
    /// for the bounded string-fallback probe (≤4 MB), never the whole
    /// file.
    func bytes(at offset: Int, count length: Int) -> [UInt8]? {
        guard offset >= 0, length >= 0, offset + length <= count else { return nil }
        return Array(UnsafeRawBufferPointer(start: basePointer + offset, count: length))
    }
}
