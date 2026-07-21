//
//  ProgramLaunchCoordinator.swift
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
import Observation

public enum ProgramLaunchPhase: Equatable, Sendable {
    case idle
    case warming(bottleName: String)
    case launching(programName: String, bottleName: String)
    case launched(programName: String)
    case failed(programName: String, message: String)
}

@MainActor
@Observable
public final class ProgramLaunchCoordinator {
    public static let shared = ProgramLaunchCoordinator()

    public private(set) var phase: ProgramLaunchPhase = .idle
    public private(set) var activeProgramURL: URL?
    public private(set) var activeBottleURL: URL?
    public private(set) var lastErrorMessage: String?

    private var launchingKeys = Set<String>()
    private var warmBottleKeys = Set<String>()
    private var warmingBottleKeys = Set<String>()
    private var dxvkReadyKeys = Set<String>()
    private var clearTask: Task<Void, Never>?

    private init() {}

    public func isWarm(bottle: Bottle) -> Bool {
        warmBottleKeys.contains(Self.bottleKey(bottle))
    }

    public func isWarming(bottle: Bottle) -> Bool {
        warmingBottleKeys.contains(Self.bottleKey(bottle))
    }

    public func isDXVKReady(bottle: Bottle) -> Bool {
        dxvkReadyKeys.contains(Self.bottleKey(bottle))
    }

    public func markDXVKReady(bottle: Bottle) {
        dxvkReadyKeys.insert(Self.bottleKey(bottle))
    }

    public func isLaunching(programURL: URL) -> Bool {
        launchingKeys.contains(Self.programKey(programURL))
    }

    public func noteAlreadyLaunching(programName: String) {
        lastErrorMessage = "「\(programName)」正在启动中，请稍候"
        phase = .failed(programName: programName, message: lastErrorMessage ?? "")
        scheduleClear(after: 2.5)
    }

    public func canStart(programURL: URL) -> Bool {
        !launchingKeys.contains(Self.programKey(programURL))
    }

    public func beginWarmup(bottle: Bottle) {
        let key = Self.bottleKey(bottle)
        guard !warmBottleKeys.contains(key) else { return }
        warmingBottleKeys.insert(key)
        if case .launching = phase {
            return
        }
        phase = .warming(bottleName: bottle.settings.name)
        activeBottleURL = bottle.url
    }

    public func finishWarmup(bottle: Bottle, success: Bool) {
        let key = Self.bottleKey(bottle)
        warmingBottleKeys.remove(key)
        if success {
            warmBottleKeys.insert(key)
        }
        if case .warming = phase {
            phase = .idle
        }
    }

    public func markWarm(bottle: Bottle) {
        warmBottleKeys.insert(Self.bottleKey(bottle))
        warmingBottleKeys.remove(Self.bottleKey(bottle))
    }

    public func clearWarm(bottle: Bottle) {
        let key = Self.bottleKey(bottle)
        warmBottleKeys.remove(key)
        warmingBottleKeys.remove(key)
    }

    public func clearAllWarm() {
        warmBottleKeys.removeAll()
        warmingBottleKeys.removeAll()
    }

    @discardableResult
    public func beginLaunch(programURL: URL, programName: String, bottle: Bottle) -> Bool {
        let key = Self.programKey(programURL)
        guard !launchingKeys.contains(key) else { return false }
        clearTask?.cancel()
        launchingKeys.insert(key)
        activeProgramURL = programURL
        activeBottleURL = bottle.url
        lastErrorMessage = nil
        phase = .launching(programName: programName, bottleName: bottle.settings.name)
        scheduleLaunchWatchdog(programURL: programURL, programName: programName)
        return true
    }

    public func finishLaunchSuccess(programURL: URL, programName: String) {
        launchingKeys.remove(Self.programKey(programURL))
        phase = .launched(programName: programName)
        scheduleClear(after: 2.5)
    }

    public func finishLaunchFailure(programURL: URL, programName: String, message: String) {
        launchingKeys.remove(Self.programKey(programURL))
        lastErrorMessage = message
        phase = .failed(programName: programName, message: message)
        scheduleClear(after: 6)
    }

    private func scheduleLaunchWatchdog(programURL: URL, programName: String) {
        let key = Self.programKey(programURL)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard launchingKeys.contains(key) else { return }
            launchingKeys.remove(key)
            if case .launching = phase {
                phase = .launched(programName: programName)
                scheduleClear(after: 2.0)
            }
        }
    }

    public func dismiss() {
        clearTask?.cancel()
        phase = .idle
        activeProgramURL = nil
        lastErrorMessage = nil
    }

    private func scheduleClear(after seconds: Double) {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if case .launching = phase {
                return
            }
            phase = .idle
            activeProgramURL = nil
        }
    }

    public static func bottleKey(_ bottle: Bottle) -> String {
        bottle.url.standardizedFileURL.path
    }

    public static func programKey(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}
