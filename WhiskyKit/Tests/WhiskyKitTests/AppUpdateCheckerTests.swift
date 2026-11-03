//
//  AppUpdateCheckerTests.swift
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

import SemanticVersion
import XCTest
@testable import WhiskyKit

final class AppUpdateCheckerTests: XCTestCase {
    private func makeChecker(body: String, status: Int = 200) -> AppUpdateChecker {
        let data = Data(body.utf8)
        return AppUpdateChecker(
            url: URL(fileURLWithPath: "/tmp/latest.json"),
            fetcher: { _ in (data, status) }
        )
    }

    private func payload(tag: String, draft: Bool = false, prerelease: Bool = false) -> String {
        """
        {"tag_name": "\(tag)", "html_url": "https://github.com/shiaho777/MacBottle/releases/tag/\(tag)",
         "draft": \(draft), "prerelease": \(prerelease)}
        """
    }

    func testParseVersion() {
        XCTAssertEqual(AppUpdateChecker.parseVersion("v2.3.5"), SemanticVersion(2, 3, 5))
        XCTAssertEqual(AppUpdateChecker.parseVersion("2.4"), SemanticVersion(2, 4, 0))
        XCTAssertEqual(AppUpdateChecker.parseVersion("V3"), SemanticVersion(3, 0, 0))
        XCTAssertEqual(AppUpdateChecker.parseVersion("v2.4.0-beta.1"), SemanticVersion(2, 4, 0))
        XCTAssertNil(AppUpdateChecker.parseVersion("latest"))
        XCTAssertNil(AppUpdateChecker.parseVersion("1.2.3.4"))
        XCTAssertNil(AppUpdateChecker.parseVersion("1..2"))
    }

    func testNewerReleaseIsAvailable() async throws {
        let status = try await makeChecker(body: payload(tag: "v2.4.0"))
            .check(currentVersion: SemanticVersion(2, 3, 5))
        guard case .available(let release) = status else {
            return XCTFail("expected available, got \(status)")
        }
        XCTAssertEqual(release.version, SemanticVersion(2, 4, 0))
        XCTAssertEqual(release.tagName, "v2.4.0")
    }

    func testSameOrOlderReleaseIsUpToDate() async throws {
        let same = try await makeChecker(body: payload(tag: "v2.3.5"))
            .check(currentVersion: SemanticVersion(2, 3, 5))
        XCTAssertEqual(same, .upToDate(current: SemanticVersion(2, 3, 5)))

        let older = try await makeChecker(body: payload(tag: "v2.0.0"))
            .check(currentVersion: SemanticVersion(2, 3, 5))
        XCTAssertEqual(older, .upToDate(current: SemanticVersion(2, 3, 5)))
    }

    func testMissingReleaseIsReportedPlainly() async throws {
        let status = try await makeChecker(body: "{}", status: 404)
            .check(currentVersion: SemanticVersion(2, 3, 5))
        XCTAssertEqual(status, .noPublishedRelease)
    }

    func testServerErrorThrows() async {
        do {
            _ = try await makeChecker(body: "", status: 500)
                .check(currentVersion: SemanticVersion(2, 3, 5))
            XCTFail("expected badResponse")
        } catch let error as AppUpdateError {
            XCTAssertEqual(error, .badResponse(500))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDraftPrereleaseAndBadTagsAreRejected() async {
        for body in [
            payload(tag: "v9.0.0", draft: true),
            payload(tag: "v9.0.0", prerelease: true),
            payload(tag: "nightly"),
            "not json"
        ] {
            do {
                _ = try await makeChecker(body: body)
                    .check(currentVersion: SemanticVersion(2, 3, 5))
                XCTFail("expected invalidPayload for \(body)")
            } catch let error as AppUpdateError {
                XCTAssertEqual(error, .invalidPayload)
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}
