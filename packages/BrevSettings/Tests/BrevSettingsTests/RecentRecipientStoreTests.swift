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

@Suite("RecentRecipientStore")
struct RecentRecipientStoreTests {
    @Test("keeps recent recipients separate and scoped to their account")
    func keepsRecentRecipientsSeparateAndScopedToTheirAccount() throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        store.record([
            RecentRecipientObservation(
                accountID: "personal",
                displayName: "Ada Lovelace",
                email: "ada@example.org",
                date: date
            ),
            RecentRecipientObservation(
                accountID: "work",
                displayName: "Grace Hopper",
                email: "grace@example.org",
                date: date.addingTimeInterval(60)
            )
        ])

        #expect(store.recipients(matching: "ada", accountID: "personal").map(\.email) == ["ada@example.org"])
        #expect(store.recipients(matching: "ada", accountID: "work").isEmpty)
        #expect(store.allRecipients().map(\.email) == ["grace@example.org", "ada@example.org"])
    }

    @Test("newer correspondence updates the local record without duplicating it")
    func newerCorrespondenceUpdatesTheLocalRecordWithoutDuplicatingIt() throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(120)

        store.record([
            RecentRecipientObservation(
                accountID: "personal",
                displayName: nil,
                email: "ada@example.org",
                date: older
            )
        ])
        store.record([
            RecentRecipientObservation(
                accountID: "personal",
                displayName: "Ada Lovelace",
                email: "ADA@example.org",
                date: newer
            )
        ])

        let recipients = store.recipients(matching: "ada", accountID: "personal")
        #expect(recipients.count == 1)
        #expect(recipients.first?.displayName == "Ada Lovelace")
        #expect(recipients.first?.lastCorrespondenceAt == newer)
    }

    @Test("older correspondence cannot replace a newer recipient display name")
    func olderCorrespondenceCannotReplaceNewerRecipientDisplayName() throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(120)

        store.record([
            RecentRecipientObservation(
                accountID: "personal",
                displayName: "Ada Lovelace",
                email: "ada@example.org",
                date: newer
            ),
            RecentRecipientObservation(
                accountID: "personal",
                displayName: "Ada Byron",
                email: "ada@example.org",
                date: older
            )
        ])

        let recipient = try #require(store.recipients(matching: "ada", accountID: "personal").first)
        #expect(recipient.displayName == "Ada Lovelace")
        #expect(recipient.lastCorrespondenceAt == newer)
    }

    @Test("recorder serializes deferred local correspondence writes")
    func recorderSerializesDeferredLocalCorrespondenceWrites() async throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let recorder = RecentRecipientRecorder(store: store)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await recorder.record([
                    RecentRecipientObservation(
                        accountID: "personal",
                        displayName: "Ada Lovelace",
                        email: "ada@example.org",
                        date: date
                    ),
                ])
            }
            group.addTask {
                await recorder.record([
                    RecentRecipientObservation(
                        accountID: "personal",
                        displayName: "Grace Hopper",
                        email: "grace@example.org",
                        date: date.addingTimeInterval(1)
                    ),
                ])
            }
        }

        #expect(store.allRecipients().map(\.email) == ["grace@example.org", "ada@example.org"])
    }

    @Test("lookup decodes recent recipients through its background actor")
    func lookupDecodesRecentRecipientsThroughItsBackgroundActor() async throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        store.record([
            RecentRecipientObservation(
                accountID: "personal",
                displayName: "Ada Lovelace",
                email: "ada@example.org",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])

        let lookup = RecentRecipientLookup(store: store)
        let recipients = await lookup.recipients(matching: "ada", accountID: "personal")

        #expect(recipients.map(\.email) == ["ada@example.org"])
    }

    @Test("removing a recipient removes every local account copy but never touches system contacts")
    func removingARecipientRemovesEveryLocalAccountCopy() throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        store.record([
            RecentRecipientObservation(accountID: "personal", displayName: "Ada", email: "ada@example.org", date: date),
            RecentRecipientObservation(accountID: "work", displayName: "Ada", email: "ada@example.org", date: date)
        ])
        store.remove(email: "ADA@example.org")

        #expect(store.allRecipients().isEmpty)
    }

    @Test("removed recipients stay dismissed until newer correspondence arrives")
    func removedRecipientsStayDismissedUntilNewerCorrespondenceArrives() throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let futureDate = Date().addingTimeInterval(60)

        store.record([
            RecentRecipientObservation(accountID: "personal", displayName: "Ada", email: "ada@example.org", date: oldDate),
        ])
        store.remove(email: "ada@example.org")
        store.record([
            RecentRecipientObservation(accountID: "personal", displayName: "Ada", email: "ada@example.org", date: oldDate),
        ])

        #expect(store.allRecipients().isEmpty)

        store.record([
            RecentRecipientObservation(
                accountID: "personal",
                displayName: "Ada Lovelace",
                email: "ada@example.org",
                date: futureDate
            ),
        ])

        #expect(store.recipients(matching: "ada", accountID: "personal").map(\.email) == ["ada@example.org"])
    }

    @Test("clearing recipients ignores cached correspondence from before the clear")
    func clearingRecipientsIgnoresCachedCorrespondenceFromBeforeTheClear() throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)

        store.record([
            RecentRecipientObservation(accountID: "personal", displayName: "Ada", email: "ada@example.org", date: oldDate),
        ])
        store.removeAll()
        store.record([
            RecentRecipientObservation(accountID: "personal", displayName: "Ada", email: "ada@example.org", date: oldDate),
        ])

        #expect(store.allRecipients().isEmpty)
    }

    @Test("account-scoped cleanup removes its recipients and dismissals")
    func accountScopedCleanupRemovesItsRecipientsAndDismissals() throws {
        let defaults = try makeDefaults()
        let store = RecentRecipientStore(defaults: defaults)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)

        store.record([
            RecentRecipientObservation(accountID: "personal", displayName: "Ada", email: "ada@example.org", date: oldDate),
            RecentRecipientObservation(accountID: "work", displayName: "Grace", email: "grace@example.org", date: oldDate),
        ])
        SettingsPersistenceStore(defaults: defaults).removeAccountScopedState(accountID: "personal")

        #expect(store.allRecipients().map(\.email) == ["grace@example.org"])
    }

    @Test("system contacts stay disabled until explicitly enabled")
    func systemContactsStayDisabledUntilExplicitlyEnabled() throws {
        let defaults = try makeDefaults()
        #expect(!RecipientSuggestionSettings.load(from: defaults).useAppleContacts)

        RecipientSuggestionSettings(useAppleContacts: false).save(to: defaults)

        #expect(!RecipientSuggestionSettings.load(from: defaults).useAppleContacts)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "RecentRecipientStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
