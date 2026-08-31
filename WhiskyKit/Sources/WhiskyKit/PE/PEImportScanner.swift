//
//  PEImportScanner.swift
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

public enum GraphicsAPI: String, Sendable, Hashable, CaseIterable {
    case d3d12
    case d3d11
    case d3d10
    case d3d9
    case d3d8
    case vulkan
    case opengl
    case unknown
}

public enum PEImportOrigin: String, Sendable, Hashable {
    case importTable
    case delayLoad
    case stringFallback
}

public struct PEImportProfile: Sendable, Hashable {
    public let architecture: Architecture
    public let importedDLLs: [String]
    public let delayLoadedDLLs: [String]
    public let graphicsAPIs: Set<GraphicsAPI>
    public let origins: [String: PEImportOrigin]

    public var preferredRenderer: RecipeRenderer {
        if graphicsAPIs.contains(.d3d12) || graphicsAPIs.contains(.d3d11) {
            return .d3dmetal
        }
        if graphicsAPIs.contains(.vulkan) || graphicsAPIs.contains(.d3d10) {
            return .dxvk
        }
        if graphicsAPIs.contains(.d3d9)
            || graphicsAPIs.contains(.d3d8)
            || graphicsAPIs.contains(.opengl) {
            return .wined3d
        }
        return .wined3d
    }

    public var primaryGraphicsAPI: GraphicsAPI {
        let order: [GraphicsAPI] = [.d3d12, .d3d11, .vulkan, .d3d10, .d3d9, .d3d8, .opengl]
        for api in order where graphicsAPIs.contains(api) {
            return api
        }
        return .unknown
    }

    public var allDLLNames: [String] {
        Array(Set(importedDLLs + delayLoadedDLLs)).sorted()
    }
}

public enum PEImportScanner {
    private static let graphicsDLLMap: [String: GraphicsAPI] = [
        "d3d12.dll": .d3d12,
        "d3d11.dll": .d3d11,
        "d3d10.dll": .d3d10,
        "d3d10_1.dll": .d3d10,
        "d3d10core.dll": .d3d10,
        "d3d9.dll": .d3d9,
        "d3d8.dll": .d3d8,
        "opengl32.dll": .opengl,
        "vulkan-1.dll": .vulkan
    ]

    private static let importDirectoryIndex: UInt32 = 1
    private static let delayImportDirectoryIndex: UInt32 = 13
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var profileCache: [String: CachedProfile] = [:]

    private struct CachedProfile {
        let modificationDate: Date
        let fileSize: UInt64
        let profile: PEImportProfile
    }

    public static func scan(url: URL) -> PEImportProfile? {
        let path = url.path(percentEncoded: false)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let modificationDate = attrs?[.modificationDate] as? Date
        let fileSize = attrs?[.size] as? UInt64

        if let modificationDate, let fileSize {
            cacheLock.lock()
            if let cached = profileCache[path],
               cached.modificationDate == modificationDate,
               cached.fileSize == fileSize {
                let profile = cached.profile
                cacheLock.unlock()
                return profile
            }
            cacheLock.unlock()
        }

        guard let profile = scanUncached(url: url) else { return nil }

        if let modificationDate, let fileSize {
            cacheLock.lock()
            profileCache[path] = CachedProfile(
                modificationDate: modificationDate,
                fileSize: fileSize,
                profile: profile
            )
            cacheLock.unlock()
        }
        return profile
    }

    public static func invalidateCache(for url: URL? = nil) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let url {
            profileCache.removeValue(forKey: url.path(percentEncoded: false))
        } else {
            profileCache.removeAll(keepingCapacity: false)
        }
    }

    private static func scanUncached(url: URL) -> PEImportProfile? {
        do {
            let peFile = try PEFile(url: url)
            guard let mapped = MappedPEView(url: url) else { return nil }

            var origins: [String: PEImportOrigin] = [:]
            let importDLLs = scanImportDirectory(peFile: peFile, mapped: mapped)
            for dll in importDLLs {
                origins[dll.lowercased()] = .importTable
            }

            let delayDLLs = scanDelayLoadDirectory(peFile: peFile, mapped: mapped)
            for dll in delayDLLs {
                let key = dll.lowercased()
                if origins[key] == nil {
                    origins[key] = .delayLoad
                }
            }

            var apis = Set<GraphicsAPI>()
            let structured = Set(importDLLs.map { $0.lowercased() })
                .union(delayDLLs.map { $0.lowercased() })
            for dll in structured {
                if let api = graphicsDLLMap[dll] {
                    apis.insert(api)
                }
            }

            var fallbackDLLs: [String] = []
            if apis.isEmpty {
                fallbackDLLs = scanFallbackStrings(mapped: mapped)
                for dll in fallbackDLLs {
                    let key = dll.lowercased()
                    if origins[key] == nil {
                        origins[key] = .stringFallback
                    }
                    if let api = graphicsDLLMap[key] {
                        apis.insert(api)
                    }
                }
            }

            return PEImportProfile(
                architecture: peFile.architecture,
                importedDLLs: importDLLs.map { $0.lowercased() }.sorted(),
                delayLoadedDLLs: delayDLLs.map { $0.lowercased() }.sorted(),
                graphicsAPIs: apis,
                origins: origins
            )
        } catch {
            return nil
        }
    }

    private static func scanImportDirectory(peFile: PEFile, mapped: MappedPEView) -> [String] {
        guard peFile.optionalHeader != nil else { return [] }
        guard let importRVA = dataDirectoryRVA(mapped: mapped, index: importDirectoryIndex),
              importRVA > 0 else {
            return []
        }
        guard let fileOffset = rvaToFileOffset(rva: importRVA, sections: peFile.sections) else {
            return []
        }

        var dlls: [String] = []
        var descriptorOffset = Int(fileOffset)
        for _ in 0..<512 {
            let originalFirstThunk = mapped.scalar(UInt32.self, at: descriptorOffset)
            let nameRVA = mapped.scalar(UInt32.self, at: descriptorOffset + 12)
            let firstThunk = mapped.scalar(UInt32.self, at: descriptorOffset + 16)
            if nameRVA == 0 && firstThunk == 0 && originalFirstThunk == 0 {
                break
            }
            if let nameOffset = rvaToFileOffset(rva: nameRVA ?? 0, sections: peFile.sections),
               let name = mapped.cString(at: Int(nameOffset), maxLength: 260) {
                dlls.append(name)
            }
            descriptorOffset += 20
        }
        return dlls
    }

    private static func scanDelayLoadDirectory(peFile: PEFile, mapped: MappedPEView) -> [String] {
        guard peFile.optionalHeader != nil else { return [] }
        guard let delayRVA = dataDirectoryRVA(mapped: mapped, index: delayImportDirectoryIndex),
              delayRVA > 0 else {
            return []
        }
        guard let fileOffset = rvaToFileOffset(rva: delayRVA, sections: peFile.sections) else {
            return []
        }

        var dlls: [String] = []
        var descriptorOffset = Int(fileOffset)
        for _ in 0..<512 {
            let attributes = mapped.scalar(UInt32.self, at: descriptorOffset)
            let nameRVA = mapped.scalar(UInt32.self, at: descriptorOffset + 4)
            let moduleHandleRVA = mapped.scalar(UInt32.self, at: descriptorOffset + 8)
            let iatRVA = mapped.scalar(UInt32.self, at: descriptorOffset + 12)
            let intRVA = mapped.scalar(UInt32.self, at: descriptorOffset + 16)
            if attributes == 0 && nameRVA == 0 && moduleHandleRVA == 0 && iatRVA == 0 && intRVA == 0 {
                break
            }
            if nameRVA != 0, let nameRVA,
               let nameOffset = rvaToFileOffset(rva: nameRVA, sections: peFile.sections),
               let name = mapped.cString(at: Int(nameOffset), maxLength: 260) {
                dlls.append(name)
            }
            descriptorOffset += 32
        }
        return dlls
    }

    private static func dataDirectoryRVA(mapped: MappedPEView, index: UInt32) -> UInt32? {
        guard let peOffset = mapped.scalar(UInt32.self, at: 0x3C) else { return nil }
        let coffOffset = Int(peOffset) + 4
        let sizeOfOptionalHeader = mapped.scalar(UInt16.self, at: coffOffset + 16)
        guard let sizeOfOptionalHeader, sizeOfOptionalHeader > 0 else { return nil }

        let optionalOffset = coffOffset + 20
        let magic = mapped.scalar(UInt16.self, at: optionalOffset)

        let numberOfRvaAndSizesOffset: Int
        let dataDirectoryBase: Int
        if magic == PEFile.Magic.pe32Plus.rawValue {
            numberOfRvaAndSizesOffset = optionalOffset + 108
            dataDirectoryBase = optionalOffset + 112
        } else if magic == PEFile.Magic.pe32.rawValue {
            numberOfRvaAndSizesOffset = optionalOffset + 92
            dataDirectoryBase = optionalOffset + 96
        } else {
            return nil
        }

        let numberOfRvaAndSizes = mapped.scalar(UInt32.self, at: numberOfRvaAndSizesOffset) ?? 0
        guard index < numberOfRvaAndSizes else { return nil }

        let entryOffset = dataDirectoryBase + Int(index) * 8
        return mapped.scalar(UInt32.self, at: entryOffset)
    }

    private static func rvaToFileOffset(rva: UInt32, sections: [PEFile.Section]) -> UInt32? {
        for section in sections {
            let start = section.virtualAddress
            let span = max(section.virtualSize, section.sizeOfRawData)
            let end = start &+ span
            if rva >= start && rva < end {
                let delta = rva &- section.virtualAddress
                return section.pointerToRawData &+ delta
            }
        }
        return nil
    }

    private static func readCString(handle: FileHandle, offset: UInt64) -> String? {
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        var bytes: [UInt8] = []
        for _ in 0..<260 {
            guard let data = try? handle.read(upToCount: 1), let byte = data.first else { break }
            if byte == 0 { break }
            bytes.append(byte)
        }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .ascii) ?? String(bytes: bytes, encoding: .utf8)
    }

    private static func scanFallbackStrings(mapped: MappedPEView) -> [String] {
        let probeLength = min(mapped.count, 4 * 1024 * 1024)
        guard var probe = mapped.bytes(at: 0, count: probeLength) else { return [] }
        let names = Array(graphicsDLLMap.keys)
        let needles = names.flatMap { [$0.asciiBytes, $0.uppercased().asciiBytes] }
        let hits = ContiguousArray(probe).firstRanges(of: needles)
        probe.removeAll(keepingCapacity: false)
        let matchedNames = Set(hits.map { $0 / 2 })
        return matchedNames.sorted().map { names[$0] }
    }
}

private extension String {
    var asciiBytes: [UInt8] {
        Array(utf8)
    }
}

private extension ContiguousArray where Element == UInt8 {
    /// Strided single-pass multi-needle search. Instead of scanning the
    /// 4 MB probe once per needle (36 full passes for the graphics DLL
    /// table, ~3.3 s on a PyInstaller launcher), every byte position is
    /// examined exactly once and matched against a first-byte index of
    /// all needles — O(n + total needle length) overall.
    func firstRanges(of needles: [[UInt8]]) -> [Int] {
        guard !needles.isEmpty, !isEmpty else { return [] }
        let byFirstByte: [UInt8: [Int]] = Dictionary(
            grouping: needles.indices,
            by: { needles[$0][0] }
        )
        var hits: [Int] = []
        var cursor = 0
        let lastStart = count - 1
        while cursor <= lastStart {
            let byte = self[cursor]
            guard let candidates = byFirstByte[byte] else {
                cursor += 1
                continue
            }
            for needleIndex in candidates {
                let needle = needles[needleIndex]
                if cursor + needle.count > count { continue }
                var probe = 1
                while probe < needle.count, self[cursor + probe] == needle[probe] {
                    probe += 1
                }
                if probe == needle.count {
                    hits.append(needleIndex)
                    cursor += needle.count - 1
                    break
                }
            }
            cursor += 1
        }
        return hits
    }
}
