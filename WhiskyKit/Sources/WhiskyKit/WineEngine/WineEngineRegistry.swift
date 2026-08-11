//
//  WineEngineRegistry.swift
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
import os.log

public final class WineEngineRegistry: @unchecked Sendable {
    public static let shared = WineEngineRegistry(loadPersisted: true)

    public static let selectionDefaultsKey = "macbottle.wineEngineID"

    public static let engineDidChangeNotification = Notification.Name("app.macbottle.engineDidChange")

    private let lock = NSLock()
    private var _current: any WineEngine

    public init(current: (any WineEngine)? = nil, loadPersisted: Bool = false) {
        if let current {
            self._current = current
            return
        }
        if loadPersisted,
           let id = UserDefaults.standard.string(forKey: Self.selectionDefaultsKey),
           let engine = WineEngineCatalog.engine(id: id),
           engine.isInstalled() {
            self._current = engine
            return
        }
        self._current = CrossOverEngine.default
    }

    public var current: any WineEngine {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    public var available: [any WineEngine] {
        WineEngineCatalog.allEngines()
    }

    public func setCurrent(_ engine: any WineEngine, persist: Bool = true) {
        lock.lock()
        let oldValue = _current.identifier
        _current = engine
        lock.unlock()
        guard oldValue != engine.identifier else { return }
        if persist {
            UserDefaults.standard.set(engine.identifier, forKey: Self.selectionDefaultsKey)
        }
        Logger.wineKit.info("WineEngineRegistry active engine: \(engine.identifier)")
        NotificationCenter.default.post(name: Self.engineDidChangeNotification, object: nil)
    }

    @discardableResult
    public func select(identifier: String, installIfNeeded: Bool = false) throws -> any WineEngine {
        if identifier == WineEngineCatalog.d3dMetalIdentifier, installIfNeeded {
            _ = try WineEngineCatalog.ensureD3DMetalEngine()
        }
        guard let engine = WineEngineCatalog.engine(id: identifier) else {
            throw WineEngineCatalogError.engineNotInstalled
        }
        guard engine.isInstalled() else {
            throw WineEngineCatalogError.engineNotInstalled
        }
        setCurrent(engine, persist: true)
        return engine
    }
}
