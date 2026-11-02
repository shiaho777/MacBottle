//
//  EngineDownloadServiceTests.swift
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

import XCTest
@testable import WhiskyKit

final class EngineDownloadServiceTests: XCTestCase {
    private var workDir: URL!
    private var url: URL {
        guard let url = URL(string: "https://stub.test/engine.tar.gz") else {
            preconditionFailure("invalid stub URL")
        }
        return url
    }

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "engine-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        RangeStub.shared.reset()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
        RangeStub.shared.reset()
    }

    private func makeService(trust: EngineArchiveTrustStore) -> EngineDownloadService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeStub.self]
        let downloader = ChunkedDownloader(
            chunkThreshold: 64 * 1024 * 1024,
            preferredChunkSize: 2 * 1024 * 1024,
            sessionConfiguration: config
        )
        return EngineDownloadService(
            trustStore: trust,
            downloader: downloader,
            validateArchive: false
        )
    }

    private func payload(_ byte: UInt8, count: Int = 512 * 1024) -> Data {
        Data(repeating: byte, count: count)
    }

    func testFirstDownloadIsRecordedAndSecondIsTrusted() async throws {
        let trust = EngineArchiveTrustStore(storeURL: workDir.appending(path: "trust.json"))
        let service = makeService(trust: trust)
        let destination = workDir.appending(path: "engine.tar.gz")
        let data = payload(0x1F)
        RangeStub.shared.payload = data

        try await service.download(from: url, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), data)
        XCTAssertEqual(
            trust.decision(url: url, sha256: ChunkedDownloader.sha256Hex(of: destination)),
            .trusted
        )

        try await service.download(from: url, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), data)
    }

    func testChangedArchiveIsRejectedUnlessAccepted() async throws {
        let trust = EngineArchiveTrustStore(storeURL: workDir.appending(path: "trust.json"))
        let service = makeService(trust: trust)
        let destination = workDir.appending(path: "engine.tar.gz")

        RangeStub.shared.payload = payload(0x1F)
        try await service.download(from: url, to: destination)
        let original = try Data(contentsOf: destination)

        RangeStub.shared.payload = payload(0x2F)
        do {
            try await service.download(from: url, to: destination)
            XCTFail("expected a changed digest to be rejected")
        } catch let error as EngineArchiveTrustError {
            guard case .digestChanged = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: destination), original, "the trusted archive must stay in place")

        try await service.download(from: url, to: destination, acceptingChangedDigest: true)
        XCTAssertEqual(try Data(contentsOf: destination), payload(0x2F))
        XCTAssertEqual(
            trust.decision(url: url, sha256: ChunkedDownloader.sha256Hex(of: destination)),
            .trusted
        )
    }

    func testTrustStoreForgetRestoresFirstUse() async throws {
        let trust = EngineArchiveTrustStore(storeURL: workDir.appending(path: "trust.json"))
        trust.record(url: url, sha256: "abc")
        XCTAssertEqual(trust.decision(url: url, sha256: "abc"), .trusted)
        trust.forget(url: url)
        XCTAssertEqual(trust.decision(url: url, sha256: "abc"), .firstUse)
    }
}
