/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import Foundation

public enum ComposeUndoSendPolicy {
    public static let delayKey = "compose.undoSendDelay"

    public static func delaySeconds(defaults: UserDefaults = .standard) -> Int {
        max(0, defaults.integer(forKey: delayKey))
    }

    public static func countdownValues(for delaySeconds: Int) -> [Int] {
        guard delaySeconds > 0 else { return [] }
        return Array(stride(from: delaySeconds, through: 1, by: -1))
    }
}
