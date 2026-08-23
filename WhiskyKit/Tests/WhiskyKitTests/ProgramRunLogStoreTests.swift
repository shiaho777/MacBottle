//
//  ProgramRunLogStoreTests.swift
//  WhiskyKitTests
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

import XCTest
@testable import WhiskyKit

@MainActor
final class ProgramRunLogStoreTests: XCTestCase {
    func testReconcileMarksDeadHostProcessAsFailed() throws {
        let bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-runlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bottleURL) }

        let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
        bottle.settings.name = "OrphanBottle"
        let programURL = bottleURL.appending(path: "drive_c/game.exe")

        let capture = try ProgramRunLogStore.shared.beginRun(programURL: programURL, bottle: bottle)
        XCTAssertEqual(capture.record.status, .running)

        ProgramRunLogStore.shared.attachHostProcess(runID: capture.record.id, processID: 2_147_483_646)
        ProgramRunLogStore.shared.reconcileStaleRunningRuns(for: bottle)

        let runs = ProgramRunLogStore.shared.runs(
            for: bottle,
            programKey: ProgramRunLogStore.programKey(for: programURL)
        )
        let record = runs.first(where: { $0.id == capture.record.id })
        XCTAssertEqual(record?.status, .failed)
        XCTAssertNotNil(record?.endedAt)
    }

    func testConcurrentPreparationsAllLandInIndex() async throws {
        let bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-runlog-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bottleURL) }

        let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
        bottle.settings.name = "RaceBottle"
        let programURL = bottleURL.appending(path: "drive_c/race.exe")
        defer { ProgramRunLogStore.shared.clearBottle(bottle) }

        let count = 16
        let captures = try await withThrowingTaskGroup(of: ProgramRunCapture.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try ProgramRunLogStore.prepareRunCapture(programURL: programURL, bottle: bottle)
                }
            }
            var results: [ProgramRunCapture] = []
            for try await capture in group {
                results.append(capture)
            }
            return results
        }
        XCTAssertEqual(captures.count, count)

        // Assert against index.json itself, not the store's merged view:
        // `runs(for:)` unions the index with live sessions, which would
        // mask exactly the lost-update bug this test guards against.
        let indexRuns = try Self.readIndexRuns(bottle: bottle, programURL: programURL)
        XCTAssertEqual(indexRuns.count, count, "every concurrent launch must survive in the index")

        for capture in captures {
            ProgramRunLogStore.shared.adoptPreparedCapture(capture)
            ProgramRunLogStore.shared.finishRun(runID: capture.record.id, exitCode: 0)
        }

        let finishedRuns = try Self.readIndexRuns(bottle: bottle, programURL: programURL)
        XCTAssertTrue(finishedRuns.allSatisfy { $0.status == .finished })
    }

    private struct BareIndex: Codable {
        var runs: [ProgramRunRecord]
    }

    private static func readIndexRuns(bottle: Bottle, programURL: URL) throws -> [ProgramRunRecord] {
        let directory = ProgramRunLogStore.rootFolder
            .appending(path: ProgramRunLogStore.bottleKey(for: bottle), directoryHint: .isDirectory)
            .appending(path: ProgramRunLogStore.programKey(for: programURL), directoryHint: .isDirectory)
        let indexURL = directory.appending(path: "index.json")
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BareIndex.self, from: data).runs
    }
}
