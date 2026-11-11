//
//  ZeroPathTests.swift
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

final class ZeroPathTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(component: "zeropath-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        PrefixReadinessOracle.resetForTests()
        LaunchLatencyTelemetry.resetForTests()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        PrefixReadinessOracle.resetForTests()
        LaunchLatencyTelemetry.resetForTests()
        super.tearDown()
    }

    private func makeFakePrefix(name: String = "prefix") -> URL {
        let prefix = workDir.appending(component: name)
        try? FileManager.default.createDirectory(
            at: prefix.appending(path: "drive_c/windows"),
            withIntermediateDirectories: true
        )
        let timestamp = prefix.appending(path: ".update-timestamp")
        try? Data("stub".utf8).write(to: timestamp)
        try? Data("stub".utf8).write(to: prefix.appending(path: "drive_c/windows/explorer.exe"))
        try? Data("[stub]\n".utf8).write(to: prefix.appending(path: "system.reg"))
        return prefix
    }

    private func fingerprint(of url: URL) -> PrefixFingerprint {
        guard let observed = PrefixReadinessOracle.observe(bottleURL: url) else {
            XCTFail("observe failed for a well-formed prefix")
            return PrefixFingerprint(
                updateTimestampMTime: .distantPast,
                updateTimestampSize: 0,
                systemRegMTime: .distantPast,
                explorerMTime: .distantPast,
                explorerSize: 0
            )
        }
        return observed
    }

    @MainActor
    func testFirstLaunchTakesConfirmingDoubleLaunch() async throws {
        let prefix = makeFakePrefix()
        let bottle = Bottle(bottleUrl: prefix, inFlight: true)
        let plan = DoubleLaunchExecutor.plan(
            bottle: bottle,
            fingerprintSaved: nil,
            engineBuildID: "crossover-3.0.0"
        )
        XCTAssertFalse(plan.readinessSkipped)
        XCTAssertTrue(plan.doubleLaunch)
    }

    @MainActor
    func testMatchingFingerprintProvesReadiness() async throws {
        let prefix = makeFakePrefix()
        let observed = fingerprint(of: prefix)
        PrefixReadinessOracle.saveBaseline(
            bottleKey: "k",
            engineBuildID: "crossover-3.0.0",
            fingerprint: observed
        )
        let baseline = PrefixReadinessOracle.loadBaseline(bottleKey: "k")
        let bottle = Bottle(bottleUrl: prefix, inFlight: true)
        let plan = DoubleLaunchExecutor.plan(
            bottle: bottle,
            fingerprintSaved: baseline,
            engineBuildID: "crossover-3.0.0"
        )
        XCTAssertTrue(plan.readinessSkipped)
        XCTAssertFalse(plan.doubleLaunch)
    }

    @MainActor
    func testBaselinesAreIndependentPerBottle() async throws {
        let prefixA = makeFakePrefix(name: "prefix-a")
        let prefixB = makeFakePrefix(name: "prefix-b")
        PrefixReadinessOracle.saveBaseline(
            bottleKey: "bottle-a",
            engineBuildID: "crossover-3.0.0",
            fingerprint: fingerprint(of: prefixA)
        )
        PrefixReadinessOracle.saveBaseline(
            bottleKey: "bottle-b",
            engineBuildID: "crossover-3.0.0",
            fingerprint: fingerprint(of: prefixB)
        )

        let planA = DoubleLaunchExecutor.plan(
            bottle: Bottle(bottleUrl: prefixA, inFlight: true),
            fingerprintSaved: PrefixReadinessOracle.loadBaseline(bottleKey: "bottle-a"),
            engineBuildID: "crossover-3.0.0"
        )
        let planB = DoubleLaunchExecutor.plan(
            bottle: Bottle(bottleUrl: prefixB, inFlight: true),
            fingerprintSaved: PrefixReadinessOracle.loadBaseline(bottleKey: "bottle-b"),
            engineBuildID: "crossover-3.0.0"
        )
        XCTAssertTrue(planA.readinessSkipped)
        XCTAssertTrue(planB.readinessSkipped, "one bottle's baseline must not evict another's")
    }

    @MainActor
    func testPrefixEvolutionInvalidatesReadiness() async throws {
        let prefix = makeFakePrefix()
        let observed = fingerprint(of: prefix)
        PrefixReadinessOracle.saveBaseline(
            bottleKey: "k",
            engineBuildID: "crossover-3.0.0",
            fingerprint: observed
        )
        // Wine upgraded the prefix: the timestamp file changed.
        let timestamp = prefix.appending(path: ".update-timestamp")
        try await Task.sleep(for: .milliseconds(20))
        try? Data("upgraded".utf8).write(to: timestamp)
        let baseline = PrefixReadinessOracle.loadBaseline(bottleKey: "k")
        let bottle = Bottle(bottleUrl: prefix, inFlight: true)
        let plan = DoubleLaunchExecutor.plan(
            bottle: bottle,
            fingerprintSaved: baseline,
            engineBuildID: "crossover-3.0.0"
        )
        XCTAssertFalse(plan.readinessSkipped)
        XCTAssertFalse(plan.doubleLaunch, "drifted baseline must not re-trigger a double launch")
    }

    @MainActor
    func testEngineUpgradeInvalidatesReadiness() async throws {
        let prefix = makeFakePrefix()
        PrefixReadinessOracle.saveBaseline(
            bottleKey: "k",
            engineBuildID: "crossover-3.0.0",
            fingerprint: fingerprint(of: prefix)
        )
        let baseline = PrefixReadinessOracle.loadBaseline(bottleKey: "k")
        let bottle = Bottle(bottleUrl: prefix, inFlight: true)
        let plan = DoubleLaunchExecutor.plan(
            bottle: bottle,
            fingerprintSaved: baseline,
            engineBuildID: "crossover-4.0.0"
        )
        XCTAssertFalse(plan.readinessSkipped)
        XCTAssertFalse(plan.doubleLaunch)
    }

    @MainActor
    func testBaselineSurvivesRegistryMutation() async throws {
        // Game runs mutate user.reg; readiness must not be affected
        // because the fingerprint excludes registry files.
        let prefix = makeFakePrefix()
        let observed = fingerprint(of: prefix)
        PrefixReadinessOracle.saveBaseline(
            bottleKey: "k",
            engineBuildID: "crossover-3.0.0",
            fingerprint: observed
        )
        try await Task.sleep(for: .milliseconds(20))
        try? Data("mutated\n".utf8).write(to: prefix.appending(path: "system.reg"))
        let baseline = PrefixReadinessOracle.loadBaseline(bottleKey: "k")
        let bottle = Bottle(bottleUrl: prefix, inFlight: true)
        let plan = DoubleLaunchExecutor.plan(
            bottle: bottle,
            fingerprintSaved: baseline,
            engineBuildID: "crossover-3.0.0"
        )
        XCTAssertTrue(plan.readinessSkipped, "registry drift must not break the ZeroPath")
    }

    func testPassRecordRoundTrip() {
        let record = DoubleLaunchExecutor.PassRecord(doubleLaunch: true, readinessSkipped: false)
        let env = DoubleLaunchExecutor.injecting(record: record, into: ["WINEDEBUG": "-all"])
        XCTAssertEqual(env["WINEDEBUG"], "-all")
        XCTAssertEqual(DoubleLaunchExecutor.passRecord(from: env), record)
        XCTAssertNil(DoubleLaunchExecutor.passRecord(from: [:]))
    }

    func testMalformedPassRecordIsIgnored() {
        XCTAssertNil(DoubleLaunchExecutor.passRecord(from: ["macbottle.doubleLaunch.pass": "not-json"]))
    }

    func testLatencyEventPersistence() {
        LaunchLatencyTelemetry.record(LaunchLatencyEvent(
            bottleKey: "k",
            startedAt: Date(),
            readinessSeconds: 0,
            dispatchSeconds: 0.4
        ))
        LaunchLatencyTelemetry.loadPersisted()
        let events = LaunchLatencyTelemetry.recentEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.dispatchSeconds ?? 0, 0.4, accuracy: 0.001)
    }
}
