//
//  LockedBoxTests.swift
//  MacBottleKit
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
@testable import MacBottleKit

final class LockedBoxTests: XCTestCase {
    func testWithLockMutatesAndReturns() {
        let box = LockedBox([String: Int]())

        box.withLock { $0["a"] = 1 }
        box.withLock { $0["b"] = 2 }

        XCTAssertEqual(box.withLock { $0 }, ["a": 1, "b": 2])
    }

    func testConcurrentIncrementsDoNotLoseUpdates() async {
        let box = LockedBox(0)
        let iterations = 500

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<iterations {
                        box.withLock { $0 += 1 }
                    }
                }
            }
        }

        XCTAssertEqual(box.withLock { $0 }, 8 * iterations)
    }

    func testReentrancyIsNotAssumed() {
        let box = LockedBox(0)
        // A plain lock must not be re-entered; verify the value is
        // readable again right after the critical section exits.
        box.withLock { $0 = 1 }
        XCTAssertEqual(box.withLock { $0 }, 1)
    }
}
