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

import Darwin
import Foundation

/// A true zero-copy, page-granular view over a file's bytes.
///
/// The previous implementation stored `Data.withUnsafeBytes`' base
/// pointer after the closure had returned. `Data` does not guarantee that
/// the pointer remains valid (or that the storage is contiguous), so that
/// was undefined behaviour. This owns an `mmap(2)` mapping explicitly and
/// unmaps it in `deinit`.
final class MappedPEView: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let basePointer: UnsafeRawPointer
    let count: Int

    init?(url: URL) {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY)
        guard descriptor >= 0 else { return nil }

        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_size > 0 else {
            close(descriptor)
            return nil
        }

        let size = Int(status.st_size)
        guard let mapped = mmap(nil, size, PROT_READ, MAP_PRIVATE, descriptor, 0),
              mapped != MAP_FAILED else {
            close(descriptor)
            return nil
        }

        self.fileDescriptor = descriptor
        self.basePointer = UnsafeRawPointer(mapped)
        self.count = size
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: basePointer), count)
        close(fileDescriptor)
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
