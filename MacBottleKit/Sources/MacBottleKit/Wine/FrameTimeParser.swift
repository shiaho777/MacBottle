//
//  FrameTimeParser.swift
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

/// Extracts real frame timings from whatever the run already logged.
///
/// There is no portable Metal/D3DMetal hook that gives a Wine process'
/// frame cadence. HUDs that print to stdout/stderr (`FPS: 60`,
/// `frametime 12.4 ms`) and games that log their own timings are the
/// only honest source. When nothing is present the parser returns an
/// empty array and the observer reports no evidence instead of guessing.
public enum FrameTimeParser {
    public struct Stats: Codable, Sendable, Equatable {
        public let sampleCount: Int
        public let averageMilliseconds: Double
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let onePercentLowFPS: Double

        public var averageFPS: Double {
            averageMilliseconds > 0 ? 1_000 / averageMilliseconds : 0
        }
    }

    private static let fpsRegex = try? NSRegularExpression(
        pattern: #"(?i)\bfps\s*[:=]?\s*([0-9]+(?:\.[0-9]+)?)"#
    )
    private static let frameTimeRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(?:frame\s*time|frametime)\s*[:=]?\s*([0-9]+(?:\.[0-9]+)?)\s*ms"#
    )
    private static let millisecondsRegex = try? NSRegularExpression(
        pattern: #"(?i)\b([0-9]+(?:\.[0-9]+)?)\s*ms\b"#
    )

    public static func parse(_ text: String) -> [Double] {
        var samples: [Double] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(line)
            if let milliseconds = firstDouble(in: line, regex: frameTimeRegex) {
                append(milliseconds, to: &samples)
                continue
            }
            if let milliseconds = firstDouble(in: line, regex: millisecondsRegex) {
                append(milliseconds, to: &samples)
                continue
            }
            if let fps = firstDouble(in: line, regex: fpsRegex), fps > 0 {
                append(1_000 / fps, to: &samples)
            }
            if samples.count >= 10_000 { break }
        }
        return samples
    }

    public static func stats(_ samples: [Double]) -> Stats? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let average = sorted.reduce(0, +) / Double(sorted.count)
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)
        // "1% low" = the average of the slowest 1% of frames, converted
        // back to FPS. With few samples, the single slowest frame is the
        // honest floor.
        let slowCount = max(1, Int(Double(sorted.count) * 0.01))
        let slowest = sorted.suffix(slowCount)
        let slowAverage = slowest.reduce(0, +) / Double(slowest.count)
        return Stats(
            sampleCount: sorted.count,
            averageMilliseconds: average,
            p50Milliseconds: p50,
            p95Milliseconds: p95,
            onePercentLowFPS: slowAverage > 0 ? 1_000 / slowAverage : 0
        )
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int(ceil(Double(sorted.count) * fraction)) - 1
        let index = min(sorted.count - 1, max(0, rank))
        return sorted[index]
    }

    private static func firstDouble(in text: String, regex: NSRegularExpression?) -> Double? {
        guard let regex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 2,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[valueRange])
    }

    private static func append(_ value: Double, to samples: inout [Double]) {
        guard value.isFinite, value >= 0.5, value <= 1_000 else { return }
        samples.append(value)
    }
}
