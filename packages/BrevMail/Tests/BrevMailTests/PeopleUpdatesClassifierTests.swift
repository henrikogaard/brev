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
import BrevDesign
@testable import BrevMail
import Foundation
import Testing

@Suite("People and Updates classification and bundling")
@MainActor
struct PeopleUpdatesClassifierTests {
    private static let source = MailSourceID(accountID: "acct", mailboxID: "box")
    private static let now = Date(timeIntervalSince1970: 1_794_500_000)

    private static func header(
        id: String,
        fromName: String? = "Maya",
        fromEmail: String = "maya@example.com",
        subject: String = "Coffee tomorrow?",
        snippet: String = "Are you free at 10?",
        minutesAgo: Double = 0,
        isRead: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: fromName, email: fromEmail),
            subject: subject,
            snippet: snippet,
            date: now.addingTimeInterval(-minutesAgo * 60),
            isRead: isRead
        )
    }

    private static func isolatedOverrideStore() -> (InboxSenderCategoryOverrideStore, () -> Void) {
        let suite = "PeopleUpdatesClassifierTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            InboxSenderCategoryOverrideStore(defaults: defaults),
            { defaults.removePersistentDomain(forName: suite) }
        )
    }

    @Test("Classifier routes List-Unsubscribe, bulk precedence, no-reply, and transactional mail to Updates")
    func classifiesUpdateSignals() {
        let (store, cleanup) = Self.isolatedOverrideStore()
        defer { cleanup() }

        let listMessage = Self.header(id: "m1", fromName: "Maya", fromEmail: "maya@digest.example", subject: "Weekly notes")
        let listResult = PeopleUpdatesClassifier.classify(
            header: listMessage,
            signals: PeopleUpdatesHeaderSignals(hasListUnsubscribe: true),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(listResult.bucket == .updates)
        #expect(listResult.signal == .listUnsubscribeHeader)

        let bulkResult = PeopleUpdatesClassifier.classify(
            header: Self.header(id: "m2", fromName: "Team", fromEmail: "team@example.com", subject: "Status"),
            signals: PeopleUpdatesHeaderSignals(isBulkPrecedence: true),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(bulkResult.bucket == .updates)
        #expect(bulkResult.signal == .bulkPrecedence)

        let noReplyResult = PeopleUpdatesClassifier.classify(
            header: Self.header(id: "m3", fromName: "Linear", fromEmail: "no-reply@linear.app", subject: "Assigned to you"),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(noReplyResult.bucket == .updates)
        #expect(noReplyResult.signal == .automatedSenderAddress)

        let receiptResult = PeopleUpdatesClassifier.classify(
            header: Self.header(
                id: "m4",
                fromName: "Acme Store",
                fromEmail: "orders@acme.example",
                subject: "Your receipt for order #42"
            ),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(receiptResult.bucket == .updates)
    }

    @Test("Classifier keeps direct people and senders the user has written to in People")
    func classifiesDirectAndRepliedSendersAsPeople() {
        let (store, cleanup) = Self.isolatedOverrideStore()
        defer { cleanup() }

        let human = Self.header(id: "m1", fromName: "Daniel", fromEmail: "daniel@example.com", subject: "Lunch?")
        let directResult = PeopleUpdatesClassifier.classify(
            header: human,
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(directResult.bucket == .people)
        #expect(directResult.signal == .directPerson)

        // Even if the subject mentions "invoice", a sender I have written to stays in People.
        let replied = Self.header(id: "m2", fromName: "Sara", fromEmail: "sara@studio.example", subject: "Re: invoice question")
        let repliedResult = PeopleUpdatesClassifier.classify(
            header: replied,
            repliedSenderEmails: ["sara@studio.example"],
            senderOverrideStore: store
        )
        #expect(repliedResult.bucket == .people)
        #expect(repliedResult.signal == .repliedToSender)
    }

    @Test("Sender overrides persist across reloads and take precedence over heuristics")
    func senderOverridesPersistAndWin() {
        let suite = "PeopleUpdatesOverride-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = InboxSenderCategoryOverrideStore(defaults: defaults)
        store.set(.people, forSenderEmail: "No-Reply@Linear.app")

        let reloaded = InboxSenderCategoryOverrideStore(defaults: defaults)
        let linear = Self.header(id: "m1", fromName: "Linear", fromEmail: "no-reply@linear.app", subject: "Notification")
        let movedToPeople = PeopleUpdatesClassifier.classify(
            header: linear,
            signals: PeopleUpdatesHeaderSignals(hasListUnsubscribe: true),
            repliedSenderEmails: [],
            senderOverrideStore: reloaded
        )
        #expect(movedToPeople.bucket == .people)
        #expect(movedToPeople.signal == .senderOverride(.people))

        reloaded.set(.updates, forSenderEmail: "daniel@example.com")
        let movedToUpdates = PeopleUpdatesClassifier.classify(
            header: Self.header(id: "m2", fromName: "Daniel", fromEmail: "daniel@example.com", subject: "Hello"),
            repliedSenderEmails: ["daniel@example.com"],
            senderOverrideStore: reloaded
        )
        #expect(movedToUpdates.bucket == .updates)
        #expect(movedToUpdates.signal == .senderOverride(.updates))
    }

    @Test("Updates bundler groups multiple messages per sender and formats summary line")
    func updatesBundlerGroupsBySender() {
        let h1 = Self.header(
            id: "m1",
            fromName: "Linear",
            fromEmail: "notifications@linear.app",
            subject: "Issue #1",
            minutesAgo: 5,
            isRead: false
        )
        let h2 = Self.header(
            id: "m2",
            fromName: "Linear",
            fromEmail: "notifications@linear.app",
            subject: "Issue #2",
            minutesAgo: 30,
            isRead: false
        )
        let h3 = Self.header(
            id: "m3",
            fromName: "GitHub",
            fromEmail: "notifications@github.com",
            subject: "PR review",
            minutesAgo: 15,
            isRead: true
        )

        let bundles = UpdatesSenderBundler.bundle([h1, h2, h3], sourceID: Self.source)
        #expect(bundles.count == 2)
        #expect(bundles[0].senderName == "Linear")
        #expect(bundles[0].headers.map(\.id) == ["m1", "m2"])
        #expect(bundles[0].unreadCount == 2)
        #expect(bundles[0].additionalCount == 1)
        #expect(bundles[0].summaryLine(locale: Locale(identifier: "en")) == "Linear 2 · 2 new · 1 more from Linear")
        #expect(bundles[1].senderName == "GitHub")
        #expect(bundles[1].headers.map(\.id) == ["m3"])
    }

    @Test("Counts on MockBackend inbox split People, Updates, and All accurately")
    func mockMailboxCounts() async throws {
        let (store, cleanup) = Self.isolatedOverrideStore()
        defer { cleanup() }

        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let headers = try await backend.messages(in: inbox, pageToken: nil).headers

        let counts = PeopleUpdatesCounts.compute(
            headers: headers,
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(counts.allCount == headers.count)
        #expect(counts.peopleCount + counts.updatesCount == counts.allCount)
        #expect(counts.peopleCount > 0)
        #expect(counts.updatesCount > 0)
    }

    @Test("Subscriptions catalog groups List-Unsubscribe senders and archives all with Undo")
    func subscriptionsCatalogAndArchiveAllWithUndo() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let archive = try #require(folders.first { $0.role == .archive })
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)

        let h1 = Self.header(
            id: "m7",
            fromName: "Coastal Post",
            fromEmail: "news@example.org",
            subject: "Edition 1",
            minutesAgo: 10
        )
        let h2 = Self.header(
            id: "newsletter-1",
            fromName: "Coastal Post",
            fromEmail: "news@example.org",
            subject: "Edition 2",
            minutesAgo: 60
        )
        let b1 = try await backend.body(for: "m7", sourceID: sourceID)
        let b2 = try await backend.body(for: "newsletter-1", sourceID: sourceID)

        let groups = SubscriptionsCatalogBuilder.build(
            candidates: [
                SubscriptionsCandidate(sourceID: sourceID, header: h1, listUnsubscribe: b1.listUnsubscribe),
                SubscriptionsCandidate(sourceID: sourceID, header: h2, listUnsubscribe: b2.listUnsubscribe),
            ]
        )

        #expect(groups.count == 1)
        #expect(groups[0].senderEmail == "news@example.org")
        #expect(groups[0].messageCount == 2)
        #expect(groups[0].lastReceived == h1.date)
        #expect(groups[0].unsubscribeOptions.requiresExplicitConfirmation)
        #expect(groups[0].confirmationSummary != nil)

        // Verify Archive all + Undo on real MockBackend messages
        let inboxHeaders = try await backend.messages(in: inbox, pageToken: nil).headers
        let target = try #require(inboxHeaders.first)
        let undoQueue = UndoQueue(timeout: 30)
        let archived = await SubscriptionsActions.archiveAll(
            headers: [target],
            sourceID: sourceID,
            from: inbox,
            to: archive,
            backend: backend,
            undoQueue: undoQueue
        )
        #expect(archived)
        let afterArchive = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(!afterArchive.contains { $0.id == target.id })

        let undone = await undoQueue.undo()?.value ?? false
        #expect(undone)
        let afterUndo = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(afterUndo.contains { $0.id == target.id })
    }

    @Test("People, Updates, and Subscriptions strings have Norwegian localizations")
    func norwegianCopy() throws {
        let catalog = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let requiredKeys = [
            "Subscriptions",
            "Unsubscribe",
            "Archive all",
            "Move sender to People",
            "Move sender to Updates",
            "No subscriptions found",
            "Archive bundle",
            "%lld messages",
            "%lld new",
            "%lld more from %@",
        ]
        for key in requiredKeys {
            let entry = try #require(catalog[key] as? [String: Any], "Missing catalog key \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let nb = try #require(localizations["nb"] as? [String: Any])
            let unitValue = (nb["stringUnit"] as? [String: Any])?["value"] as? String
            let hasVariations = (nb["variations"] as? [String: Any]) != nil
            #expect((unitValue?.isEmpty == false) || hasVariations, "Missing nb localization for \(key)")
        }
    }
}
