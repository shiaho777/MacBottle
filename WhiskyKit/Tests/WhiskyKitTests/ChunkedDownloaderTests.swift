//
//  ChunkedDownloaderTests.swift
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

import CryptoKit
import XCTest
@testable import WhiskyKit

final class ChunkedDownloaderTests: XCTestCase {

    private var workRoot: URL!
    private let stubURL: URL = {
        guard let url = URL(string: "https://stub.test/file") else {
            preconditionFailure("invalid stub URL")
        }
        return url
    }()

    override func setUpWithError() throws {
        workRoot = FileManager.default.temporaryDirectory
            .appending(path: "macbottle-chunked-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        RangeStub.shared.reset()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workRoot)
        RangeStub.shared.reset()
    }

    private func makePayload(_ megabytes: Int) -> Data {
        let count = megabytes * 1024 * 1024
        var data = Data(capacity: count)
        for offset in 0..<count {
            data.append(UInt8((offset / 7919) % 251))
        }
        return data
    }

    private func makeDownloader(chunkThreshold: Int64, preferredChunkSize: Int64) -> ChunkedDownloader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeStub.self]
        return ChunkedDownloader(
            chunkThreshold: chunkThreshold,
            preferredChunkSize: preferredChunkSize,
            sessionConfiguration: config
        )
    }

    private func rangeString(start: Int64, end: Int64) -> String {
        "bytes=\(start)-\(end)"
    }

    func testParallelDownloadAssemblesExactBytes() async throws {
        let payload = makePayload(5)
        RangeStub.shared.payload = payload

        let destination = workRoot.appending(path: "game.bin")
        let downloader = makeDownloader(chunkThreshold: 1024 * 1024, preferredChunkSize: 2 * 1024 * 1024)

        try await downloader.download(jobs: [
            DownloadJob(url: stubURL, destination: destination,
                        expectedSize: Int64(payload.count))
        ])

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        let partsDir = workRoot.appending(path: ".game.bin.parts")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partsDir.path))
    }

    func testParallelResumeReusesCompleteParts() async throws {
        let payload = makePayload(6)
        RangeStub.shared.payload = payload

        let destination = workRoot.appending(path: "big.pkg")
        let downloader = makeDownloader(chunkThreshold: 1024 * 1024, preferredChunkSize: 2 * 1024 * 1024)

        // 6 MB at 2 MB chunks → three ranges; fail the middle one so the
        // first attempt dies after its siblings completed.
        let middleRange = rangeString(start: 2 * 1024 * 1024, end: 4 * 1024 * 1024 - 1)
        RangeStub.shared.failRanges.insert(middleRange)

        do {
            try await downloader.download(jobs: [
                DownloadJob(url: stubURL, destination: destination,
                            expectedSize: Int64(payload.count))
            ])
            XCTFail("expected the interrupted attempt to throw")
        } catch {
            // expected
        }

        let partsDir = workRoot.appending(path: ".big.pkg.parts")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: partsDir.path).sorted(),
            ["part-0000", "part-0002"],
            "completed parts must survive the failed attempt"
        )

        RangeStub.shared.requestedRanges.removeAll()
        RangeStub.shared.failRanges.removeAll()
        try await downloader.download(jobs: [
            DownloadJob(url: stubURL, destination: destination,
                        expectedSize: Int64(payload.count))
        ])

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        let rangeRequests = RangeStub.shared.requestedRanges.filter { $0 != "none" && $0.hasPrefix("bytes=") }
        XCTAssertEqual(rangeRequests, [middleRange], "retry must fetch only the missing range")
    }

    func testSmallFileResumeAppendsRemainder() async throws {
        let payload = makePayload(2)
        RangeStub.shared.payload = payload

        let destination = workRoot.appending(path: "small.dat")
        let partial = destination.appendingPathExtension("partial")
        let half = payload.prefix(payload.count / 2)
        try half.write(to: partial)

        let downloader = makeDownloader(chunkThreshold: 64 * 1024 * 1024, preferredChunkSize: 2 * 1024 * 1024)

        try await downloader.download(jobs: [
            DownloadJob(url: stubURL, destination: destination,
                        expectedSize: Int64(payload.count))
        ])

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    // MARK: - Checksum verification

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testMatchingChecksumAcceptsDownload() async throws {
        let payload = makePayload(1)
        RangeStub.shared.payload = payload

        let destination = workRoot.appending(path: "checked.bin")
        let downloader = makeDownloader(chunkThreshold: 64 * 1024 * 1024, preferredChunkSize: 2 * 1024 * 1024)

        try await downloader.download(jobs: [
            DownloadJob(url: stubURL, destination: destination,
                        expectedSize: Int64(payload.count),
                        expectedSha256: Self.sha256Hex(payload))
        ])

        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }

    func testChecksumMismatchFailsAndDiscardsFile() async throws {
        let payload = makePayload(1)
        RangeStub.shared.payload = payload

        let destination = workRoot.appending(path: "corrupt.bin")
        let downloader = makeDownloader(chunkThreshold: 64 * 1024 * 1024, preferredChunkSize: 2 * 1024 * 1024)

        do {
            try await downloader.download(jobs: [
                DownloadJob(url: stubURL, destination: destination,
                            expectedSize: Int64(payload.count),
                            expectedSha256: String(repeating: "0", count: 64))
            ])
            XCTFail("expected checksum mismatch to throw")
        } catch let error as DownloadError {
            guard case .checksumMismatch = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.path),
            "a file that failed verification must not be left behind"
        )
    }

    func testSameSizeCorruptFileIsRedownloaded() async throws {
        let payload = makePayload(1)
        RangeStub.shared.payload = payload

        let destination = workRoot.appending(path: "stale.bin")
        // Same size as the real payload but wrong content: the old
        // size-only shortcut would trust it and skip the download.
        try Data(count: payload.count).write(to: destination)

        let downloader = makeDownloader(chunkThreshold: 64 * 1024 * 1024, preferredChunkSize: 2 * 1024 * 1024)

        try await downloader.download(jobs: [
            DownloadJob(url: stubURL, destination: destination,
                        expectedSize: Int64(payload.count),
                        expectedSha256: Self.sha256Hex(payload))
        ])

        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }
}

/// Serves one fixed payload over HTTP semantics inside the URL loading
/// system: HEAD probes advertise Accept-Ranges, GETs honor Range headers
/// with 206 responses, and configured ranges fail with a network error
/// so tests can simulate interrupted transfers.
final class RangeStub: URLProtocol, @unchecked Sendable {

    static let shared = StubState()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.httpMethod == "HEAD" {
            let length = String(Self.shared.payload.count)
            respond(status: 200, body: Data(), headers: [
                "Accept-Ranges": "bytes",
                "Content-Length": length
            ])
            return
        }

        let range = request.value(forHTTPHeaderField: "Range")
        Self.shared.record(range ?? "none")

        if let range, Self.shared.failRanges.contains(range) {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }

        if let range, let bounds = Self.parseRange(range) {
            let body = Self.shared.slice(offset: bounds.offset, length: bounds.length)
            respond(status: 206, body: body, headers: ["Content-Length": String(body.count)])
        } else {
            let body = Self.shared.payload
            respond(status: 200, body: body, headers: ["Content-Length": String(body.count)])
        }
    }

    override func stopLoading() {}

    private func respond(status: Int, body: Data, headers: [String: String]) {
        guard let url = request.url else { return }
        let http = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )
        guard let http else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func parseRange(_ header: String) -> (offset: Int, length: Int)? {
        guard header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int(parts[0]) else { return nil }
        if let end = Int(parts[1]) {
            return (start, end - start + 1)
        }
        return (start, max(0, Self.shared.payload.count - start))
    }
}

final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var _payload = Data()
    private var _failRanges: Set<String> = []
    private var _requestedRanges: [String] = []

    var payload: Data {
        get { lock.withLock { _payload } }
        set { lock.withLock { _payload = newValue } }
    }
    var failRanges: Set<String> {
        get { lock.withLock { _failRanges } }
        set { lock.withLock { _failRanges = newValue } }
    }
    var requestedRanges: [String] {
        get { lock.withLock { _requestedRanges } }
        set { lock.withLock { _requestedRanges = newValue } }
    }

    func reset() {
        lock.withLock {
            _payload = Data()
            _failRanges = []
            _requestedRanges = []
        }
    }

    func record(_ range: String) {
        lock.withLock { _requestedRanges.append(range) }
    }

    func slice(offset: Int, length: Int) -> Data {
        lock.withLock { _payload.subdata(in: offset..<offset + length) }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
