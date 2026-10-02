/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files ("the Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

@testable import BrevSettings
import Foundation
import Testing

@Suite("Blocked senders settings")
struct BlockedSendersSettingsTests {
    @Test("save posts the didChange notification")
    func savePostsDidChange() {
        let suite = "BrevBlockedSendersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var didPost = false
        let observer = NotificationCenter.default.addObserver(
            forName: BlockedSendersSettings.Key.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            didPost = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        var settings = BlockedSendersSettings(blockedEmails: [])
        settings.block("noise@example.com")
        settings.save(to: defaults)

        #expect(didPost)
    }

    @Test("block and unblock round-trip through defaults")
    func blockUnblockRoundTrip() {
        let suite = "BrevBlockedSendersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = BlockedSendersSettings(blockedEmails: [])
        settings.block("Noise@Example.com")
        settings.save(to: defaults)

        let loaded = BlockedSendersSettings.load(from: defaults)
        #expect(loaded.isBlocked("noise@example.com"))

        var unblocked = loaded
        unblocked.unblock("noise@example.com")
        unblocked.save(to: defaults)

        #expect(!BlockedSendersSettings.load(from: defaults).isBlocked("noise@example.com"))
    }
}
