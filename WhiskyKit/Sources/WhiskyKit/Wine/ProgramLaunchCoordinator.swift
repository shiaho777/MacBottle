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

    public func isWarm(bottle: Bottle, engineID: String) -> Bool {
        warmBottleKeys.contains(Self.warmKey(bottle: bottle, engineID: engineID))
    }

    public func isWarming(bottle: Bottle, engineID: String) -> Bool {
        warmingBottleKeys.contains(Self.warmKey(bottle: bottle, engineID: engineID))
    }

    public func isDXVKReady(bottle: Bottle, engineID: String) -> Bool {
        dxvkReadyKeys.contains(Self.warmKey(bottle: bottle, engineID: engineID))
    }

    public func markDXVKReady(bottle: Bottle, engineID: String) {
        dxvkReadyKeys.insert(Self.warmKey(bottle: bottle, engineID: engineID))
    }

    public func clearDXVK(bottle: Bottle) {
        let prefix = Self.bottleKey(bottle) + "|"
        dxvkReadyKeys = dxvkReadyKeys.filter { !$0.hasPrefix(prefix) }
    }

    /// Drop every piece of state that is only valid for the engine that
    /// produced it. Called when the user switches engines: a prefix warmed
    /// by CrossOver is not warm under GPTK, and DXVK DLLs copied from one
    /// engine must not be reused under another.
    public func invalidateEngineBoundState() {
        warmBottleKeys.removeAll()
        warmingBottleKeys.removeAll()
        dxvkReadyKeys.removeAll()
        if case .warming = phase {
            phase = .idle
        }
    }

    /// Drop engine-bound state for one bottle (delete, rename, force stop).
    public func invalidate(bottle: Bottle) {
        let prefix = Self.bottleKey(bottle) + "|"
        warmBottleKeys = warmBottleKeys.filter { !$0.hasPrefix(prefix) }
        warmingBottleKeys = warmingBottleKeys.filter { !$0.hasPrefix(prefix) }
        dxvkReadyKeys = dxvkReadyKeys.filter { !$0.hasPrefix(prefix) }
    }

    public func isLaunching(programURL: URL) -> Bool {
        launchingKeys.contains(Self.programKey(programURL))
    }

    public func noteAlreadyLaunching(programName: String) {
        lastErrorMessage = String(format: String(localized: "launch.alreadyLaunching %@"), programName)
        phase = .failed(programName: programName, message: lastErrorMessage ?? "")
        scheduleClear(after: 2.5)
    }

    public func canStart(programURL: URL) -> Bool {
        !launchingKeys.contains(Self.programKey(programURL))
    }

    nonisolated public static func silentExitFailureMessage(
        secondsToExit: TimeInterval,
        processOutputByteCount: UInt64,
        quietWindow: TimeInterval = 5
    ) -> String? {
        guard processOutputByteCount == 0,
              secondsToExit >= 0,
              secondsToExit < quietWindow else {
            return nil
        }
        return String(
            format: String(localized: "bottle.launch.silentExit %lld"),
            Int(secondsToExit.rounded())
        )
    }

    nonisolated public static func silentExitFailureMessage(capture: ProgramRunCapture) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: capture.fileURL.path(percentEncoded: false)
        ), let size = (attrs[.size] as? NSNumber)?.uint64Value else {
            return nil
        }
        let outputBytes = size > capture.outputStartOffset
            ? size - capture.outputStartOffset
            : 0
        return silentExitFailureMessage(
            secondsToExit: Date().timeIntervalSince(capture.record.startedAt),
            processOutputByteCount: outputBytes
        )
    }

    public func beginWarmup(bottle: Bottle, engineID: String) {
        let key = Self.warmKey(bottle: bottle, engineID: engineID)
        guard !warmBottleKeys.contains(key) else { return }
        warmingBottleKeys.insert(key)
        if case .launching = phase {
            return
        }
        phase = .warming(bottleName: bottle.settings.name)
        activeBottleURL = bottle.url
    }

    public func finishWarmup(bottle: Bottle, engineID: String, success: Bool) {
        let key = Self.warmKey(bottle: bottle, engineID: engineID)
        warmingBottleKeys.remove(key)
        if success {
            warmBottleKeys.insert(key)
        }
        if case .warming = phase {
            phase = .idle
        }
    }

    public func markWarm(bottle: Bottle, engineID: String) {
        let key = Self.warmKey(bottle: bottle, engineID: engineID)
        warmBottleKeys.insert(key)
        warmingBottleKeys.remove(key)
    }

    public func clearWarm(bottle: Bottle) {
        let prefix = Self.bottleKey(bottle) + "|"
        warmBottleKeys = warmBottleKeys.filter { !$0.hasPrefix(prefix) }
        warmingBottleKeys = warmingBottleKeys.filter { !$0.hasPrefix(prefix) }
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

    public func reportSilentExit(programURL: URL, message: String) {
        guard isLaunching(programURL: programURL) else { return }
        finishLaunchFailure(
            programURL: programURL,
            programName: programURL.lastPathComponent,
            message: message
        )
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

    static func warmKey(bottle: Bottle, engineID: String) -> String {
        "\(bottleKey(bottle))|\(engineID)"
    }

    public static func programKey(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}
