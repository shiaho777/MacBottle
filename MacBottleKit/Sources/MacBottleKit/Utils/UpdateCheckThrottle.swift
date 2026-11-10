//
//  UpdateCheckThrottle.swift
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

import Foundation

/// Keeps launch-time network checks from running on every app start.
public enum UpdateCheckThrottle {
    public static let engineInterval: TimeInterval = 24 * 60 * 60

    public static func shouldCheck(
        last: Date?,
        now: Date = Date(),
        interval: TimeInterval = engineInterval
    ) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last)
        // A clock moved backwards should not lock the check out.
        return elapsed < 0 || elapsed >= interval
    }
}
