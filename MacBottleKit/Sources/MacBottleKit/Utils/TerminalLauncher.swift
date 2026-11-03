//
//  TerminalLauncher.swift
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
import os.log

public enum TerminalLauncher {
    public static func run(command: String) async throws {
        let fileManager = FileManager.default
        let scriptURL = fileManager.temporaryDirectory
            .appending(path: "macbottle-\(UUID().uuidString).command")
        let body = """
        #!/bin/zsh
        \(command)
        exec /bin/zsh -i
        """
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path(percentEncoded: false)
        )

        let result = try await ProcessRunner.run(
            path: "/usr/bin/open",
            arguments: ["-a", "Terminal", scriptURL.path(percentEncoded: false)]
        )
        if !result.isSuccess {
            Logger.wineKit.error("TerminalLauncher open failed with status \(result.exitCode)")
            throw TerminalLauncherError.openFailed(status: result.exitCode)
        }
    }
}

public enum TerminalLauncherError: Error {
    case openFailed(status: Int32)
}
