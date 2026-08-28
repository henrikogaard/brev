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
import BrevSettings
import Foundation
import Testing

@Suite("InboxClassificationPolicy")
struct InboxClassificationPolicyTests {
    @Test("disabled settings leave all messages visible")
    func disabledSettingsLeaveAllMessagesVisible() {
        let headers = [
            Self.header(subject: "Receipt for order 123"),
            Self.header(subject: "Dinner tonight?", from: "Ada", email: "ada@example.org")
        ]

        let visible = InboxClassificationVisibilityPolicy.headers(
            headers,
            sourceID: Self.source,
            selectedCategory: .transactions,
            settings: InboxClassificationSettings(mode: .off),
            overrideStore: .empty
        )

        #expect(visible.map(\.subject) == headers.map(\.subject))
    }

    @Test("receipt and invoice signals classify as transactions with an explanation")
    func receiptSignalsClassifyAsTransactions() {
        let header = Self.header(
            subject: "Invoice INV-42 paid",
            snippet: "Your receipt is attached",
            email: "billing@example.com"
        )

        let result = InboxClassificationPolicy.classification(
            for: header,
            sourceID: Self.source,
            overrideStore: .empty
        )

        #expect(result.category == .transactions)
        #expect(result.reason == .matchedKeyword("invoice"))
    }

    @Test("newsletter and offer signals classify as promotions")
    func newsletterSignalsClassifyAsPromotions() {
        let header = Self.header(
            subject: "Summer offer",
            snippet: "Unsubscribe from this newsletter",
            email: "deals@example.com"
        )

        let result = InboxClassificationPolicy.classification(
            for: header,
            sourceID: Self.source,
            overrideStore: .empty
        )

        #expect(result.category == .promotions)
        #expect(result.reason == .matchedKeyword("unsubscribe"))
    }

    @Test("notification senders classify as updates")
    func notificationSendersClassifyAsUpdates() {
        let header = Self.header(
            subject: "Security alert",
            snippet: "A new sign-in was detected",
            email: "noreply@example.com"
        )

        let result = InboxClassificationPolicy.classification(
            for: header,
            sourceID: Self.source,
            overrideStore: .empty
        )

        #expect(result.category == .updates)
        #expect(result.reason == .matchedKeyword("security alert"))
    }

    @Test("human direct messages classify as primary")
    func directMessagesClassifyAsPrimary() {
        let header = Self.header(
            subject: "Project notes",
            snippet: "Can you look at this after lunch?",
            from: "Ada Lovelace",
            email: "ada@example.org"
        )

        let result = InboxClassificationPolicy.classification(
            for: header,
            sourceID: Self.source,
            overrideStore: .empty
        )

        #expect(result.category == .primary)
        #expect(result.reason == .directMessage)
    }

    @Test("manual overrides win over heuristic category")
    func manualOverridesWin() throws {
        let defaults = try Self.makeDefaults()
        let store = InboxCategoryOverrideStore(defaults: defaults)
        let header = Self.header(id: "message-1", subject: "Invoice paid")
        store.set(.primary, for: SourceMessageID(sourceID: Self.source, messageID: "message-1"))

        let result = InboxClassificationPolicy.classification(
            for: header,
            sourceID: Self.source,
            overrideStore: store
        )

        #expect(result.category == .primary)
        #expect(result.reason == .manualOverride)
    }

    @Test("category visibility filters by source-aware classification")
    func visibilityFiltersByClassification() throws {
        let defaults = try Self.makeDefaults()
        let store = InboxCategoryOverrideStore(defaults: defaults)
        let direct = Self.header(id: "direct", subject: "Coffee?")
        let receipt = Self.header(id: "receipt", subject: "Receipt for order")
        store.set(.primary, for: SourceMessageID(sourceID: Self.source, messageID: "receipt"))

        let visible = InboxClassificationVisibilityPolicy.headers(
            [direct, receipt],
            sourceID: Self.source,
            selectedCategory: .primary,
            settings: InboxClassificationSettings(mode: .categories),
            overrideStore: store
        )

        #expect(visible.map(\.id) == ["direct", "receipt"])
    }

    private static let source = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")

    private static func header(
        id: MessageHeader.ID = UUID().uuidString,
        subject: String,
        snippet: String = "",
        from name: String = "Sender",
        email: String = "sender@example.org"
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: name, email: email),
            subject: subject,
            snippet: snippet,
            date: Date(),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "InboxClassificationPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
