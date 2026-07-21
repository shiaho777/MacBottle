//
//  ProgramRunLogStore.swift
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
import Darwin
import Observation
import CryptoKit
import os.log

public enum ProgramRunStatus: String, Codable, Sendable, Hashable {
    case running
    case finished
    case failed
}

public enum ProgramRunLogSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case failedFirst
    case longest

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newest: return "最新优先"
        case .oldest: return "最旧优先"
        case .failedFirst: return "失败优先"
        case .longest: return "时长优先"
        }
    }
}

public struct ProgramRunRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var programKey: String
    public var programName: String
    public var programPath: String
    public var bottleKey: String
    public var bottleName: String
    public var bottlePath: String
    public var startedAt: Date
    public var endedAt: Date?
    public var exitCode: Int32?
    public var status: ProgramRunStatus
    public var fileName: String
    public var byteCount: Int
    public var hostProcessID: Int32?

    public var duration: TimeInterval {
        let end = endedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }

    public var statusLabel: String {
        switch status {
        case .running: return "运行中"
        case .finished: return "已结束"
        case .failed: return "失败"
        }
    }
}

public struct ProgramRunProgramSummary: Identifiable, Hashable, Sendable {
    public var id: String { programKey }
    public var programKey: String
    public var programName: String
    public var programPath: String
    public var runCount: Int
    public var lastStartedAt: Date?
    public var hasRunning: Bool
}

@MainActor
@Observable
public final class ProgramRunLogSession: Identifiable {
    public let id: UUID
    public private(set) var record: ProgramRunRecord
    public private(set) var lines: [String] = []
    public private(set) var text: String = ""

    public var isLive: Bool { record.status == .running }

    fileprivate init(record: ProgramRunRecord) {
        self.id = record.id
        self.record = record
    }

    fileprivate func append(line: String) {
        lines.append(line)
        if lines.count > 8000 {
            lines.removeFirst(lines.count - 8000)
        }
        text.append(line)
        if text.count > 2_000_000 {
            text = String(text.suffix(1_500_000))
        }
    }

    fileprivate func update(record: ProgramRunRecord) {
        self.record = record
    }

    fileprivate func replaceText(_ value: String) {
        text = value
        lines = value.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) + "\n" }
        if lines.count > 8000 {
            lines = Array(lines.suffix(8000))
        }
    }
}

private struct ProgramRunIndexFile: Codable {
    var runs: [ProgramRunRecord]
}

public struct ProgramRunCapture: @unchecked Sendable {
    public let record: ProgramRunRecord
    public let fileHandle: FileHandle
    public let fileURL: URL
}

@MainActor
@Observable
public final class ProgramRunLogStore {
    public static let shared = ProgramRunLogStore()
    nonisolated public static let verboseWineDebugDefaultsKey = "macbottle.verboseWineDebug"
    nonisolated public static let verboseWineDebugChannels =
        "+timestamp,+tid,+err,+seh,+loaddll,+module,+process,+thread,+pid,fixme-all"

    nonisolated public static var verboseWineDebugEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: verboseWineDebugDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: verboseWineDebugDefaultsKey) }
    }

    public private(set) var sessions: [UUID: ProgramRunLogSession] = [:]
    public var revision: Int = 0

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    nonisolated public static var rootFolder: URL {
        Wine.logsFolder.appending(path: "ProgramRuns", directoryHint: .isDirectory)
    }

    nonisolated public static let previewMaxBytes = 128 * 1024
    nonisolated public static let captureMaxBytes = 12 * 1024 * 1024

    private init() {}

    nonisolated public static func bottleKey(for bottle: Bottle) -> String {
        stableKey(for: bottle.url.standardizedFileURL.path(percentEncoded: false))
    }

    nonisolated public static func programKey(for url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let base = url.deletingPathExtension().lastPathComponent
        let safe = sanitize(base)
        return "\(safe)-\(stableKey(for: path))"
    }
    nonisolated public static func prepareRunCapture(
        programURL: URL,
        bottle: Bottle
    ) throws -> ProgramRunCapture {
        let bottleKey = bottleKey(for: bottle)
        let programKey = programKey(for: programURL)
        let runID = UUID()
        let fileName = "\(runID.uuidString).log"
        let directory = programDirectory(bottleKey: bottleKey, programKey: programKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appending(path: fileName)
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forWritingTo: fileURL)

        let record = ProgramRunRecord(
            id: runID,
            programKey: programKey,
            programName: programURL.lastPathComponent,
            programPath: programURL.standardizedFileURL.path(percentEncoded: false),
            bottleKey: bottleKey,
            bottleName: bottle.settings.name,
            bottlePath: bottle.url.standardizedFileURL.path(percentEncoded: false),
            startedAt: Date(),
            endedAt: nil,
            exitCode: nil,
            status: .running,
            fileName: fileName,
            byteCount: 0,
            hostProcessID: nil
        )

        handle.writeApplicationInfo()
        handle.writeInfo(for: bottle)
        handle.write(line: "Program: \(record.programName)\n")
        handle.write(line: "Program Path: \(record.programPath)\n")
        handle.write(line: "Run ID: \(runID.uuidString)\n")
        let debugMode = verboseWineDebugEnabled
            ? "verbose (\(verboseWineDebugChannels))"
            : "performance (WINEDEBUG=-all)"
        handle.write(line: "Capture Mode: \(debugMode)\n")
        handle.write(line: "---- begin process output ----\n\n")

        var index = loadIndexStatic(bottleKey: bottleKey, programKey: programKey)
        index.runs.insert(record, at: 0)
        try saveIndexStatic(index, bottleKey: bottleKey, programKey: programKey)

        return ProgramRunCapture(record: record, fileHandle: handle, fileURL: fileURL)
    }
    public func beginRun(
        programURL: URL,
        bottle: Bottle
    ) throws -> ProgramRunCapture {
        let capture = try Self.prepareRunCapture(programURL: programURL, bottle: bottle)
        adoptPreparedCapture(capture)
        return capture
    }
    public func adoptPreparedCapture(_ capture: ProgramRunCapture) {
        guard sessions[capture.record.id] == nil else { return }
        sessions[capture.record.id] = ProgramRunLogSession(record: capture.record)
        bump()
    }
    public func appendLine(runID: UUID, line: String, isError: Bool = false) {
        guard let session = sessions[runID] else { return }
        let prefix = isError ? "[stderr] " : ""
        let entry = line.hasSuffix("\n") ? "\(prefix)\(line)" : "\(prefix)\(line)\n"
        session.append(line: entry)
        if session.lines.count % 24 == 0 {
            bump()
        }
    }
    public func noteHeartbeat(runID: UUID, tick: Int, processID: Int32) {
        guard let session = sessions[runID] else { return }
        let line = "[heartbeat] still running (tick \(tick), pid \(processID))\n"
        session.append(line: line)
        bump()
    }
    public func attachHostProcess(runID: UUID, processID: Int32) {
        if let session = sessions[runID] {
            var record = session.record
            record.hostProcessID = processID
            session.update(record: record)
            var index = loadIndex(bottleKey: record.bottleKey, programKey: record.programKey)
            if let idx = index.runs.firstIndex(where: { $0.id == runID }) {
                index.runs[idx] = record
                try? saveIndex(index, bottleKey: record.bottleKey, programKey: record.programKey)
            }
            bump()
            return
        }
        guard var record = findRecordInIndexes(runID: runID) else { return }
        record.hostProcessID = processID
        var index = loadIndex(bottleKey: record.bottleKey, programKey: record.programKey)
        if let idx = index.runs.firstIndex(where: { $0.id == runID }) {
            index.runs[idx] = record
            try? saveIndex(index, bottleKey: record.bottleKey, programKey: record.programKey)
        }
        bump()
    }

    public func finishRun(runID: UUID, exitCode: Int32?) {
        guard var record = sessions[runID]?.record
            ?? findRecord(runID: runID)
            ?? findRecordInIndexes(runID: runID) else { return }
        if record.status != .running, record.endedAt != nil {
            return
        }
        record.endedAt = Date()
        record.exitCode = exitCode
        if let exitCode, exitCode != 0 {
            record.status = .failed
        } else {
            record.status = .finished
        }
        let fileURL = logFileURL(for: record)
        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path(percentEncoded: false)),
           let size = attrs[.size] as? NSNumber {
            record.byteCount = size.intValue
        }

        var index = loadIndex(bottleKey: record.bottleKey, programKey: record.programKey)
        if let idx = index.runs.firstIndex(where: { $0.id == runID }) {
            index.runs[idx] = record
        } else {
            index.runs.insert(record, at: 0)
        }
        try? saveIndex(index, bottleKey: record.bottleKey, programKey: record.programKey)

        if let session = sessions[runID] {
            session.update(record: record)
            if let content = Self.readTailText(url: fileURL, maxBytes: 400_000), !content.isEmpty {
                session.replaceText(content)
            }
        }

        bump()
    }

    public func liveSession(for id: UUID?) -> ProgramRunLogSession? {
        guard let id else { return nil }
        return sessions[id]
    }

    public func programs(for bottle: Bottle, sort: ProgramRunLogSort = .newest) -> [ProgramRunProgramSummary] {
        let bottleKey = Self.bottleKey(for: bottle)
        let root = Self.bottleDirectory(bottleKey: bottleKey)
        guard let programDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return mergeRunningPrograms(for: bottleKey, into: [])
        }

        var summaries: [ProgramRunProgramSummary] = []
        for dir in programDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path(percentEncoded: false), isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let programKey = dir.lastPathComponent
            let index = loadIndex(bottleKey: bottleKey, programKey: programKey)
            guard let first = index.runs.first else { continue }
            let hasRunning = index.runs.contains(where: { $0.status == .running })
                || sessions.values.contains(where: { $0.record.programKey == programKey && $0.isLive })
            let last = index.runs.map(\.startedAt).max()
            summaries.append(
                ProgramRunProgramSummary(
                    programKey: programKey,
                    programName: first.programName,
                    programPath: first.programPath,
                    runCount: index.runs.count,
                    lastStartedAt: last,
                    hasRunning: hasRunning
                )
            )
        }

        summaries = mergeRunningPrograms(for: bottleKey, into: summaries)
        switch sort {
        case .newest, .failedFirst, .longest:
            summaries.sort { ($0.lastStartedAt ?? .distantPast) > ($1.lastStartedAt ?? .distantPast) }
        case .oldest:
            summaries.sort { ($0.lastStartedAt ?? .distantFuture) < ($1.lastStartedAt ?? .distantFuture) }
        }
        return summaries
    }

    public func runs(
        for bottle: Bottle,
        programKey: String,
        sort: ProgramRunLogSort = .newest
    ) -> [ProgramRunRecord] {
        let bottleKey = Self.bottleKey(for: bottle)
        var runs = loadIndex(bottleKey: bottleKey, programKey: programKey).runs
        for session in sessions.values where session.record.programKey == programKey
            && session.record.bottleKey == bottleKey {
            if let idx = runs.firstIndex(where: { $0.id == session.id }) {
                runs[idx] = session.record
            } else {
                runs.insert(session.record, at: 0)
            }
        }
        return sortRuns(runs, by: sort)
    }

    public func allRuns(for bottle: Bottle, sort: ProgramRunLogSort = .newest) -> [ProgramRunRecord] {
        let programs = programs(for: bottle, sort: sort)
        var all: [ProgramRunRecord] = []
        for program in programs {
            all.append(contentsOf: runs(for: bottle, programKey: program.programKey, sort: sort))
        }
        return sortRuns(all, by: sort)
    }

    public func logFileURL(for record: ProgramRunRecord) -> URL {
        Self.programDirectory(bottleKey: record.bottleKey, programKey: record.programKey)
            .appending(path: record.fileName)
    }

    public func readLogText(for record: ProgramRunRecord) -> String {
        if let session = sessions[record.id], !session.text.isEmpty {
            return session.text
        }
        return Self.readTailText(url: logFileURL(for: record), maxBytes: Self.previewMaxBytes) ?? ""
    }

    nonisolated public static func readPreviewText(url: URL, maxBytes: Int = 128 * 1024) -> String {
        let body = readTailText(url: url, maxBytes: maxBytes) ?? ""
        if body.isEmpty { return body }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxBytes {
            return "[showing last \(maxBytes) bytes of \(size.intValue)-byte log]\n\n" + body
        }
        return body
    }

    public func loadSessionText(for record: ProgramRunRecord) -> ProgramRunLogSession {
        let preview = Self.readPreviewText(url: logFileURL(for: record), maxBytes: Self.previewMaxBytes)
        if let existing = sessions[record.id] {
            existing.replaceText(preview)
            return existing
        }
        let session = ProgramRunLogSession(record: record)
        session.replaceText(preview)
        sessions[record.id] = session
        return session
    }

    public func deleteRuns(_ records: [ProgramRunRecord]) {
        var grouped: [String: [ProgramRunRecord]] = [:]
        for record in records {
            let key = "\(record.bottleKey)|\(record.programKey)"
            grouped[key, default: []].append(record)
        }

        for (_, group) in grouped {
            guard let first = group.first else { continue }
            var index = loadIndex(bottleKey: first.bottleKey, programKey: first.programKey)
            let ids = Set(group.map(\.id))
            for record in group {
                let url = logFileURL(for: record)
                try? fileManager.removeItem(at: url)
                sessions[record.id] = nil
            }
            index.runs.removeAll { ids.contains($0.id) }
            try? saveIndex(index, bottleKey: first.bottleKey, programKey: first.programKey)
            if index.runs.isEmpty {
                let dir = Self.programDirectory(bottleKey: first.bottleKey, programKey: first.programKey)
                try? fileManager.removeItem(at: dir)
            }
        }
        bump()
    }

    public func clearProgram(bottle: Bottle, programKey: String) {
        let bottleKey = Self.bottleKey(for: bottle)
        let index = loadIndex(bottleKey: bottleKey, programKey: programKey)
        deleteRuns(index.runs)
        for session in sessions.values where session.record.bottleKey == bottleKey
            && session.record.programKey == programKey {
            sessions[session.id] = nil
        }
        let dir = Self.programDirectory(bottleKey: bottleKey, programKey: programKey)
        try? fileManager.removeItem(at: dir)
        bump()
    }

    public func clearBottle(_ bottle: Bottle) {
        let bottleKey = Self.bottleKey(for: bottle)
        let root = Self.bottleDirectory(bottleKey: bottleKey)
        if let programDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) {
            for dir in programDirs {
                try? fileManager.removeItem(at: dir)
            }
        }
        for session in sessions.values where session.record.bottleKey == bottleKey {
            sessions[session.id] = nil
        }
        try? fileManager.removeItem(at: root)
        bump()
    }

    public func exportRun(_ record: ProgramRunRecord, to destination: URL) throws {
        let source = logFileURL(for: record)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func mergeRunningPrograms(
        for bottleKey: String,
        into summaries: [ProgramRunProgramSummary]
    ) -> [ProgramRunProgramSummary] {
        var map = Dictionary(uniqueKeysWithValues: summaries.map { ($0.programKey, $0) })
        for session in sessions.values where session.record.bottleKey == bottleKey {
            let key = session.record.programKey
            if var existing = map[key] {
                existing.hasRunning = existing.hasRunning || session.isLive
                existing.runCount = max(existing.runCount, 1)
                if let last = existing.lastStartedAt {
                    existing.lastStartedAt = max(last, session.record.startedAt)
                } else {
                    existing.lastStartedAt = session.record.startedAt
                }
                map[key] = existing
            } else {
                map[key] = ProgramRunProgramSummary(
                    programKey: key,
                    programName: session.record.programName,
                    programPath: session.record.programPath,
                    runCount: 1,
                    lastStartedAt: session.record.startedAt,
                    hasRunning: session.isLive
                )
            }
        }
        return Array(map.values)
    }

    private func sortRuns(_ runs: [ProgramRunRecord], by sort: ProgramRunLogSort) -> [ProgramRunRecord] {
        switch sort {
        case .newest:
            return runs.sorted { $0.startedAt > $1.startedAt }
        case .oldest:
            return runs.sorted { $0.startedAt < $1.startedAt }
        case .failedFirst:
            return runs.sorted { lhs, rhs in
                if lhs.status == .failed && rhs.status != .failed { return true }
                if lhs.status != .failed && rhs.status == .failed { return false }
                return lhs.startedAt > rhs.startedAt
            }
        case .longest:
            return runs.sorted { $0.duration > $1.duration }
        }
    }

    private func findRecord(runID: UUID) -> ProgramRunRecord? {
        if let session = sessions[runID] {
            return session.record
        }
        return nil
    }

    public func markBottleRunsInterrupted(bottle: Bottle) {
        let bottleKey = Self.bottleKey(for: bottle)
        let root = Self.bottleDirectory(bottleKey: bottleKey)
        guard let programDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            for session in sessions.values where session.record.bottleKey == bottleKey && session.isLive {
                finishRun(runID: session.id, exitCode: 137)
            }
            bump()
            return
        }

        for dir in programDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path(percentEncoded: false), isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let programKey = dir.lastPathComponent
            var index = loadIndex(bottleKey: bottleKey, programKey: programKey)
            var changed = false
            for idx in index.runs.indices where index.runs[idx].status == .running {
                var record = index.runs[idx]
                record.endedAt = Date()
                record.exitCode = 137
                record.status = .failed
                index.runs[idx] = record
                if let session = sessions[record.id] {
                    session.update(record: record)
                    session.append(line: "\n---- force stopped (runtime interrupted) ----\n")
                }
                changed = true
            }
            if changed {
                try? saveIndex(index, bottleKey: bottleKey, programKey: programKey)
            }
        }
        for session in sessions.values where session.record.bottleKey == bottleKey && session.isLive {
            finishRun(runID: session.id, exitCode: 137)
        }
        bump()
    }

    public func reconcileStaleRunningRuns(for bottle: Bottle) {
        let bottleKey = Self.bottleKey(for: bottle)
        let root = Self.bottleDirectory(bottleKey: bottleKey)
        guard let programDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            reconcileLiveSessions(bottleKey: bottleKey)
            return
        }

        for dir in programDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path(percentEncoded: false), isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let programKey = dir.lastPathComponent
            var index = loadIndex(bottleKey: bottleKey, programKey: programKey)
            var changed = false
            for idx in index.runs.indices where index.runs[idx].status == .running {
                var record = index.runs[idx]
                if shouldKeepRunning(record) {
                    continue
                }
                record.endedAt = Date()
                record.status = .failed
                if record.exitCode == nil {
                    record.exitCode = -1
                }
                index.runs[idx] = record
                if let session = sessions[record.id] {
                    session.update(record: record)
                }
                changed = true
                appendStaleNote(for: record)
            }
            if changed {
                try? saveIndex(index, bottleKey: bottleKey, programKey: programKey)
            }
        }
        reconcileLiveSessions(bottleKey: bottleKey)
        bump()
    }

    private func reconcileLiveSessions(bottleKey: String) {
        for session in sessions.values where session.record.bottleKey == bottleKey && session.isLive {
            if shouldKeepRunning(session.record) {
                continue
            }
            finishRun(runID: session.id, exitCode: session.record.exitCode ?? -1)
        }
    }

    private func shouldKeepRunning(_ record: ProgramRunRecord) -> Bool {
        if let session = sessions[record.id], session.isLive {
            if let pid = record.hostProcessID ?? session.record.hostProcessID {
                return Self.isHostProcessAlive(pid)
            }
            return true
        }
        if let pid = record.hostProcessID {
            return Self.isHostProcessAlive(pid)
        }
        return false
    }

    private static func isHostProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    private func appendStaleNote(for record: ProgramRunRecord) {
        let url = logFileURL(for: record)
        let note = "\n---- process ended unexpectedly (status reconciled) ----\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = note.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
        if let session = sessions[record.id] {
            session.append(line: note)
        }
    }

    private func findRecordInIndexes(runID: UUID) -> ProgramRunRecord? {
        for session in sessions.values where session.id == runID {
            return session.record
        }
        guard let bottleDirs = try? fileManager.contentsOfDirectory(
            at: Self.rootFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for bottleDir in bottleDirs {
            guard let programDirs = try? fileManager.contentsOfDirectory(
                at: bottleDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for programDir in programDirs {
                let index = loadIndex(
                    bottleKey: bottleDir.lastPathComponent,
                    programKey: programDir.lastPathComponent
                )
                if let record = index.runs.first(where: { $0.id == runID }) {
                    return record
                }
            }
        }
        return nil
    }
    private func loadIndex(bottleKey: String, programKey: String) -> ProgramRunIndexFile {
        Self.loadIndexStatic(bottleKey: bottleKey, programKey: programKey)
    }
    private func saveIndex(_ index: ProgramRunIndexFile, bottleKey: String, programKey: String) throws {
        try Self.saveIndexStatic(index, bottleKey: bottleKey, programKey: programKey)
    }
    nonisolated private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    nonisolated private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    nonisolated private static func loadIndexStatic(bottleKey: String, programKey: String) -> ProgramRunIndexFile {
        let url = indexURL(bottleKey: bottleKey, programKey: programKey)
        guard let data = try? Data(contentsOf: url),
              let index = try? makeDecoder().decode(ProgramRunIndexFile.self, from: data) else {
            return ProgramRunIndexFile(runs: [])
        }
        return index
    }
    nonisolated private static func saveIndexStatic(
        _ index: ProgramRunIndexFile,
        bottleKey: String,
        programKey: String
    ) throws {
        let directory = programDirectory(bottleKey: bottleKey, programKey: programKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try makeEncoder().encode(index)
        try data.write(to: indexURL(bottleKey: bottleKey, programKey: programKey), options: .atomic)
    }

    nonisolated private static func bottleDirectory(bottleKey: String) -> URL {
        rootFolder.appending(path: bottleKey, directoryHint: .isDirectory)
    }

    nonisolated private static func programDirectory(bottleKey: String, programKey: String) -> URL {
        bottleDirectory(bottleKey: bottleKey).appending(path: programKey, directoryHint: .isDirectory)
    }

    nonisolated private static func indexURL(bottleKey: String, programKey: String) -> URL {
        programDirectory(bottleKey: bottleKey, programKey: programKey).appending(path: "index.json")
    }

    nonisolated private static func stableKey(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(scalars)
        if result.isEmpty { return "program" }
        return String(result.prefix(48))
    }

    nonisolated public static func readTailText(url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size <= maxBytes {
            try? handle.seek(toOffset: 0)
        } else {
            try? handle.seek(toOffset: size - UInt64(maxBytes))
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    private func bump() {
        revision &+= 1
    }
}
