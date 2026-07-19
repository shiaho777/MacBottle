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
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var origins: [String: PEImportOrigin] = [:]
            let importDLLs = scanImportDirectory(peFile: peFile, handle: handle)
            for dll in importDLLs {
                origins[dll.lowercased()] = .importTable
            }

            let delayDLLs = scanDelayLoadDirectory(peFile: peFile, handle: handle)
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
                fallbackDLLs = scanFallbackStrings(handle: handle)
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

    private static func scanImportDirectory(peFile: PEFile, handle: FileHandle) -> [String] {
        guard peFile.optionalHeader != nil else { return [] }
        guard let importRVA = dataDirectoryRVA(handle: handle, index: importDirectoryIndex),
              importRVA > 0 else {
            return []
        }
        guard let fileOffset = rvaToFileOffset(rva: importRVA, sections: peFile.sections) else {
            return []
        }

        var dlls: [String] = []
        var descriptorOffset = UInt64(fileOffset)
        for _ in 0..<512 {
            let originalFirstThunk = handle.extract(UInt32.self, offset: descriptorOffset) ?? 0
            let nameRVA = handle.extract(UInt32.self, offset: descriptorOffset + 12) ?? 0
            let firstThunk = handle.extract(UInt32.self, offset: descriptorOffset + 16) ?? 0
            if nameRVA == 0 && firstThunk == 0 && originalFirstThunk == 0 {
                break
            }
            if let nameOffset = rvaToFileOffset(rva: nameRVA, sections: peFile.sections),
               let name = readCString(handle: handle, offset: UInt64(nameOffset)) {
                dlls.append(name)
            }
            descriptorOffset += 20
        }
        return dlls
    }

    private static func scanDelayLoadDirectory(peFile: PEFile, handle: FileHandle) -> [String] {
        guard peFile.optionalHeader != nil else { return [] }
        guard let delayRVA = dataDirectoryRVA(handle: handle, index: delayImportDirectoryIndex),
              delayRVA > 0 else {
            return []
        }
        guard let fileOffset = rvaToFileOffset(rva: delayRVA, sections: peFile.sections) else {
            return []
        }

        var dlls: [String] = []
        var descriptorOffset = UInt64(fileOffset)
        for _ in 0..<512 {
            let attributes = handle.extract(UInt32.self, offset: descriptorOffset) ?? 0
            let nameRVA = handle.extract(UInt32.self, offset: descriptorOffset + 4) ?? 0
            let moduleHandleRVA = handle.extract(UInt32.self, offset: descriptorOffset + 8) ?? 0
            let iatRVA = handle.extract(UInt32.self, offset: descriptorOffset + 12) ?? 0
            let intRVA = handle.extract(UInt32.self, offset: descriptorOffset + 16) ?? 0
            if attributes == 0 && nameRVA == 0 && moduleHandleRVA == 0 && iatRVA == 0 && intRVA == 0 {
                break
            }
            if nameRVA != 0,
               let nameOffset = rvaToFileOffset(rva: nameRVA, sections: peFile.sections),
               let name = readCString(handle: handle, offset: UInt64(nameOffset)) {
                dlls.append(name)
            }
            descriptorOffset += 32
        }
        return dlls
    }

    private static func dataDirectoryRVA(handle: FileHandle, index: UInt32) -> UInt32? {
        guard let peOffset = handle.extract(UInt32.self, offset: 0x3C) else { return nil }
        let coffOffset = UInt64(peOffset) + 4
        let sizeOfOptionalHeader = handle.extract(UInt16.self, offset: coffOffset + 16) ?? 0
        guard sizeOfOptionalHeader > 0 else { return nil }

        let optionalOffset = coffOffset + 20
        let magic = handle.extract(UInt16.self, offset: optionalOffset) ?? 0

        let numberOfRvaAndSizesOffset: UInt64
        let dataDirectoryBase: UInt64
        if magic == PEFile.Magic.pe32Plus.rawValue {
            numberOfRvaAndSizesOffset = optionalOffset + 108
            dataDirectoryBase = optionalOffset + 112
        } else if magic == PEFile.Magic.pe32.rawValue {
            numberOfRvaAndSizesOffset = optionalOffset + 92
            dataDirectoryBase = optionalOffset + 96
        } else {
            return nil
        }

        let numberOfRvaAndSizes = handle.extract(UInt32.self, offset: numberOfRvaAndSizesOffset) ?? 0
        guard index < numberOfRvaAndSizes else { return nil }

        let entryOffset = dataDirectoryBase + UInt64(index) * 8
        return handle.extract(UInt32.self, offset: entryOffset)
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

    private static func scanFallbackStrings(handle: FileHandle) -> [String] {
        do {
            try handle.seek(toOffset: 0)
            guard let data = try handle.read(upToCount: 4 * 1024 * 1024) else { return [] }
            var found: [String] = []
            for name in graphicsDLLMap.keys {
                let needles = [name, name.uppercased()]
                for needle in needles {
                    guard let pattern = needle.data(using: .ascii) else { continue }
                    if data.range(of: pattern) != nil {
                        found.append(name)
                        break
                    }
                }
            }
            return found
        } catch {
            return []
        }
    }
}
