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

@testable import BrevSettings
import Foundation
import Testing

@Suite("ComposeSettings")
struct ComposeSettingsTests {
    @Test("defaults are conservative and local-only")
    func defaultsAreConservativeAndLocalOnly() throws {
        let defaults = try Self.makeDefaults()

        let settings = ComposeSettings.load(from: defaults)

        #expect(settings.messageFormat == .automatic)
        #expect(settings.attachmentReminderEnabled)
        #expect(settings.externalRecipientWarningEnabled)
        #expect(settings.quotePlacement == .belowReply)
        #expect(settings.undoSendDelay == .off)
        #expect(settings.textCheckingEnabled)
    }

    @Test("saving and loading preserves compose defaults")
    func savingAndLoadingPreservesComposeDefaults() throws {
        let defaults = try Self.makeDefaults()
        let settings = ComposeSettings(
            messageFormat: .plainText,
            attachmentReminderEnabled: false,
            externalRecipientWarningEnabled: false,
            quotePlacement: .aboveReply,
            undoSendDelay: .tenSeconds,
            textCheckingEnabled: false
        )

        settings.save(to: defaults)
        let restored = ComposeSettings.load(from: defaults)

        #expect(restored == settings)
    }

    @Test("invalid compose enum values fall back to defaults")
    func invalidComposeEnumValuesFallBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("stone-tablet", forKey: ComposeSettings.Key.messageFormat)
        defaults.set("folded-note", forKey: ComposeSettings.Key.quotePlacement)
        defaults.set(99, forKey: ComposeSettings.Key.undoSendDelay)

        let settings = ComposeSettings.load(from: defaults)

        #expect(settings.messageFormat == .automatic)
        #expect(settings.quotePlacement == .belowReply)
        #expect(settings.undoSendDelay == .off)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "ComposeSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
