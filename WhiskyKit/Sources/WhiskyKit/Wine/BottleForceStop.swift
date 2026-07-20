//
//  BottleForceStop.swift
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
import os.log

public final class BottleProcessRegistry: @unchecked Sendable {
    public static let shared = BottleProcessRegistry()

    private let lock = NSLock()
    private var processes: [String: [Process]] = [:]

    private init() {}

    public func register(_ process: Process, bottle: Bottle) {
        let key = Self.key(for: bottle)
        lock.lock()
        defer { lock.unlock() }
        var list = processes[key] ?? []
        list = list.filter { $0.isRunning }
        list.append(process)
        processes[key] = list
    }

    public func unregisterFinished(for bottle: Bottle) {
        let key = Self.key(for: bottle)
        lock.lock()
        defer { lock.unlock() }
        processes[key] = (processes[key] ?? []).filter { $0.isRunning }
        if processes[key]?.isEmpty == true {
            processes[key] = nil
        }
    }

    public func registeredProcesses(for bottle: Bottle) -> [Process] {
        let key = Self.key(for: bottle)
        lock.lock()
        defer { lock.unlock() }
        let list = (processes[key] ?? []).filter { $0.isRunning }
        processes[key] = list
        return list
    }

    public func allRegisteredProcesses() -> [Process] {
        lock.lock()
        defer { lock.unlock() }
        return processes.values.flatMap { $0 }.filter(\.isRunning)
    }

    public static func key(for bottle: Bottle) -> String {
        bottle.url.standardizedFileURL.path
    }
}

public enum BottleForceStop {
    public static func forceStop(bottle: Bottle, reason: String = "force-stop") {
        let prefix = bottle.url.standardizedFileURL.path
        Logger.wineKit.warning("BottleForceStop \(reason) for \(prefix, privacy: .public)")

        for process in BottleProcessRegistry.shared.registeredProcesses(for: bottle) {
            hardKill(process: process)
        }

        requestWineserverKill(prefix: prefix)
        let hostPIDs = hostPIDs(matchingPrefix: prefix)
        for pid in hostPIDs {
            hardKill(pid: pid)
        }

        BottleProcessRegistry.shared.unregisterFinished(for: bottle)
        Task { @MainActor in
            ProgramRunLogStore.shared.markBottleRunsInterrupted(bottle: bottle)
        }
    }

    public static func forceStopAllBottles(bottles: [Bottle]) {
        for bottle in bottles {
            forceStop(bottle: bottle, reason: "app-terminate")
        }
        for process in BottleProcessRegistry.shared.allRegisteredProcesses() {
            hardKill(process: process)
        }
    }

    private static func requestWineserverKill(prefix: String) {
        let wineserver = WhiskyWineInstaller.binFolder.appending(path: "wineserver")
        guard FileManager.default.fileExists(atPath: wineserver.path) else { return }

        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-k"]
        process.environment = [
            "WINEPREFIX": prefix,
            "WINEDEBUG": "-all",
            "PATH": WhiskyWineInstaller.binFolder.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }
            if group.wait(timeout: .now() + 1.5) == .timedOut {
                hardKill(process: process)
            }
        } catch {
            Logger.wineKit.error(
                "BottleForceStop wineserver -k failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func hostPIDs(matchingPrefix prefix: String) -> [Int32] {
        let needle = prefix
        var pids = Set<Int32>()

        var nameBytes = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        var buffer = [pid_t](repeating: 0, count: 4096)
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, Int32(MemoryLayout<pid_t>.stride * buffer.count))
        let processCount = Int(count) / MemoryLayout<pid_t>.stride
        guard processCount > 0 else { return [] }

        for index in 0..<min(processCount, buffer.count) {
            let pid = buffer[index]
            guard pid > 0 else { continue }
            nameBytes = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
            let pathLen = proc_pidpath(pid, &nameBytes, UInt32(nameBytes.count))
            guard pathLen > 0 else { continue }
            guard let path = String(bytes: nameBytes.prefix(Int(pathLen)), encoding: .utf8) else { continue }
            let base = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            let isWineBinary = base == "wine"
                || base == "wine64"
                || base == "wineserver"
                || base.hasPrefix("wine")
            guard isWineBinary else { continue }

            if processMentionsPrefix(pid: pid, prefix: needle) {
                pids.insert(pid)
            }
        }
        return Array(pids)
    }

    private static func processMentionsPrefix(pid: Int32, prefix: String) -> Bool {
        if let args = processArguments(pid: pid), args.contains(where: { $0.contains(prefix) }) {
            return true
        }
        if let env = processEnvironment(pid: pid) {
            if env["WINEPREFIX"] == prefix { return true }
            if env.values.contains(where: { $0.contains(prefix) }) { return true }
        }
        return false
    }

    private static func processArguments(pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size == 0 {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        guard buffer.count >= 4 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < buffer.count && buffer[index] != 0 { index += 1 }
        while index < buffer.count && buffer[index] == 0 { index += 1 }

        var args: [String] = []
        for _ in 0..<argc {
            if index >= buffer.count { break }
            let start = index
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            if start < index {
                let slice = buffer[start..<index]
                if let string = String(bytes: slice, encoding: .utf8) {
                    args.append(string)
                }
            }
            index += 1
        }
        return args
    }

    private static func processEnvironment(pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size == 0 {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        guard buffer.count >= 4 else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < buffer.count && buffer[index] != 0 { index += 1 }
        while index < buffer.count && buffer[index] == 0 { index += 1 }
        for _ in 0..<max(argc, 0) {
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            index += 1
        }
        while index < buffer.count && buffer[index] == 0 { index += 1 }

        var env: [String: String] = [:]
        while index < buffer.count {
            let start = index
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            if start == index { break }
            if let entry = String(bytes: buffer[start..<index], encoding: .utf8),
               let separator = entry.firstIndex(of: "=") {
                let key = String(entry[..<separator])
                let value = String(entry[entry.index(after: separator)...])
                env[key] = value
            }
            index += 1
            if index < buffer.count && buffer[index] == 0 { break }
        }
        return env
    }

    private static func hardKill(process: Process) {
        let pid = process.processIdentifier
        if process.isRunning {
            process.terminate()
        }
        usleep(120_000)
        if process.isRunning {
            hardKill(pid: pid)
        }
    }

    private static func hardKill(pid: Int32) {
        guard pid > 1 else { return }
        kill(pid, SIGTERM)
        usleep(80_000)
        kill(pid, SIGKILL)
    }
}
