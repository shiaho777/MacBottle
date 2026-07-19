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
}
