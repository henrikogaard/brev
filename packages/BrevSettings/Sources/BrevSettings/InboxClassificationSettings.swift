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

import BrevDesign
import Foundation

public struct InboxClassificationSettings: Equatable, Sendable {
    public var mode: InboxClassificationMode

    public init(mode: InboxClassificationMode) {
        self.mode = mode
    }

    public static let defaults = InboxClassificationSettings(mode: .off)

    public static func load(from defaults: UserDefaults = .standard) -> InboxClassificationSettings {
        guard let rawMode = defaults.string(forKey: MailboxViewPreferenceKey.inboxClassificationMode),
              let mode = InboxClassificationMode(rawValue: rawMode) else {
            return Self.defaults
        }
        return InboxClassificationSettings(mode: mode)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: MailboxViewPreferenceKey.inboxClassificationMode)
    }
}
