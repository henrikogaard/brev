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

import BrevBackend
import Foundation
import Testing

@Suite("MailboxSourcePreferences")
struct MailboxSourcePreferencesTests {
    private let work = MailSourceID(accountID: "acct-1", mailboxID: "work")
    private let personal = MailSourceID(accountID: "acct-1", mailboxID: "personal")
    private let shared = MailSourceID(accountID: "acct-1", mailboxID: "shared")

    @Test("empty preferences enable every available source")
    func emptyPreferencesEnableEveryAvailableSource() {
        let available = [work, personal, shared]

        #expect(MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: available,
            preferences: .defaults
        ) == available)
    }

    @Test("stored enabled sources are filtered and kept in available order")
    func storedEnabledSourcesAreFilteredInAvailableOrder() {
        let unavailable = MailSourceID(accountID: "acct-2", mailboxID: "old")
        let preferences = MailboxSourcePreferences(
            enabledSourceIDs: [shared, unavailable, work],
            defaultSourceID: shared
        )

        #expect(MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: [work, personal, shared],
            preferences: preferences
        ) == [work, shared])
    }

    @Test("default falls back to preferred provider mailbox")
    func defaultFallsBackToPreferredProviderMailbox() {
        let preferences = MailboxSourcePreferences(
            enabledSourceIDs: [work, personal],
            defaultSourceID: shared
        )

        #expect(MailboxSourcePreferencesPolicy.defaultSourceID(
            availableSourceIDs: [work, personal, shared],
            preferences: preferences,
            preferredDefaultSourceID: personal
        ) == personal)
    }

    @Test("normalization keeps at least one enabled source and enabled default")
    func normalizationKeepsAtLeastOneEnabledSourceAndDefault() {
        let preferences = MailboxSourcePreferencesPolicy.normalized(
            availableSourceIDs: [work, personal],
            enabledSourceIDs: [],
            defaultSourceID: shared,
            preferredDefaultSourceID: personal
        )

        #expect(preferences.enabledSourceIDs == [work, personal])
        #expect(preferences.defaultSourceID == personal)
    }

    @Test("storage round trips preferences")
    func storageRoundTripsPreferences() throws {
        let defaults = try Self.makeDefaults()
        let preferences = MailboxSourcePreferences(
            enabledSourceIDs: [work],
            defaultSourceID: work
        )

        MailboxSourcePreferencesStorage.save(preferences, to: defaults)

        #expect(MailboxSourcePreferencesStorage.load(from: defaults) == preferences)
    }

    @Test("removing an account clears its sources and default")
    func removingAccountClearsSourcesAndDefault() throws {
        let defaults = try Self.makeDefaults()
        let other = MailSourceID(accountID: "acct-2", mailboxID: "other")
        MailboxSourcePreferencesStorage.save(
            MailboxSourcePreferences(enabledSourceIDs: [work, other], defaultSourceID: work),
            to: defaults
        )

        MailboxSourcePreferencesStorage.removeAccount("acct-1", from: defaults)

        #expect(MailboxSourcePreferencesStorage.load(from: defaults) == MailboxSourcePreferences(
            enabledSourceIDs: [other],
            defaultSourceID: nil
        ))
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "MailboxSourcePreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
