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
@testable import BrevSettings
import Foundation
import Testing

@Suite("InboxClassificationSettings")
struct InboxClassificationSettingsTests {
    @Test("defaults keep classification disabled until the user opts in")
    func defaultsKeepClassificationDisabled() throws {
        let defaults = try Self.makeDefaults()

        let settings = InboxClassificationSettings.load(from: defaults)

        #expect(settings.mode == .off)
    }

    @Test("saving and loading preserves the selected classification mode")
    func savingAndLoadingPreservesMode() throws {
        let defaults = try Self.makeDefaults()
        let settings = InboxClassificationSettings(mode: .categories)

        settings.save(to: defaults)
        let restored = InboxClassificationSettings.load(from: defaults)

        #expect(restored == settings)
    }

    @Test("invalid mode raw value falls back to disabled")
    func invalidModeFallsBackToDisabled() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("server-ai", forKey: MailboxViewPreferenceKey.inboxClassificationMode)

        let settings = InboxClassificationSettings.load(from: defaults)

        #expect(settings.mode == .off)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "InboxClassificationSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
