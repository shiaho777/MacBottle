//
//  ProcessRunner.swift
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

public struct ProcessRunResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public var standardOutputString: String {
        String(data: standardOutput, encoding: .utf8)
            ?? String(data: standardOutput, encoding: .isoLatin1)
            ?? ""
    }

    public var standardErrorString: String {
        String(data: standardError, encoding: .utf8)
            ?? String(data: standardError, encoding: .isoLatin1)
            ?? ""
    }

    public var isSuccess: Bool {
        exitCode == 0
    }
}

public enum ProcessRunner {
    public static func run(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessRunResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            if let environment {
                process.environment = environment
            }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { finished in
                let outData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(
                    returning: ProcessRunResult(
                        exitCode: finished.terminationStatus,
                        standardOutput: outData,
                        standardError: errData
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public static func run(
        path: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessRunResult {
        try await run(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment
        )
    }
}
