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
@testable import BrevMail
import Foundation
import Testing

@Suite("Message read receipt notification store")
struct MessageReadReceiptNotificationStoreTests {
    @Test("records received receipts by account and original message id")
    func recordsByAccountAndOriginalMessageID() throws {
        let suiteName = "MessageReadReceiptNotificationStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MessageReadReceiptNotificationStore(defaults: defaults, maxRecords: 10)
        let receivedAt = Date(timeIntervalSince1970: 1800)

        store.record(
            ReadReceiptNotification(
                finalRecipient: "reader@example.com",
                originalMessageID: "<original@example.org>",
                disposition: "manual-action/MDN-sent-manually; displayed"
            ),
            receiptMessageID: "INBOX:42",
            receivedAt: receivedAt,
            accountID: "account-a"
        )

        #expect(store.notifications(
            forOriginalMessageID: "original@example.org",
            accountID: "account-a"
        ) == [
            MessageReadReceiptNotificationRecord(
                originalMessageID: "<original@example.org>",
                finalRecipient: "reader@example.com",
                disposition: "manual-action/MDN-sent-manually; displayed",
                receiptMessageID: "INBOX:42",
                receivedAt: receivedAt
            )
        ])
        #expect(store.notifications(
            forOriginalMessageID: "<original@example.org>",
            accountID: "account-b"
        ).isEmpty)
    }

    @Test("updates duplicate receipt message and caps newest records")
    func updatesDuplicatesAndCapsNewestRecords() throws {
        let suiteName = "MessageReadReceiptNotificationStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MessageReadReceiptNotificationStore(defaults: defaults, maxRecords: 2)

        store.record(
            ReadReceiptNotification(
                finalRecipient: "first@example.com",
                originalMessageID: "<first@example.org>",
                disposition: "manual-action/MDN-sent-manually; displayed"
            ),
            receiptMessageID: "INBOX:1",
            receivedAt: Date(timeIntervalSince1970: 1),
            accountID: "account-a"
        )
        store.record(
            ReadReceiptNotification(
                finalRecipient: "second@example.com",
                originalMessageID: "<second@example.org>",
                disposition: "manual-action/MDN-sent-manually; displayed"
            ),
            receiptMessageID: "INBOX:2",
            receivedAt: Date(timeIntervalSince1970: 2),
            accountID: "account-a"
        )
        store.record(
            ReadReceiptNotification(
                finalRecipient: "second-updated@example.com",
                originalMessageID: "<second@example.org>",
                disposition: "manual-action/MDN-sent-manually; displayed"
            ),
            receiptMessageID: "INBOX:2",
            receivedAt: Date(timeIntervalSince1970: 3),
            accountID: "account-a"
        )
        store.record(
            ReadReceiptNotification(
                finalRecipient: "third@example.com",
                originalMessageID: "<third@example.org>",
                disposition: "manual-action/MDN-sent-manually; displayed"
            ),
            receiptMessageID: "INBOX:3",
            receivedAt: Date(timeIntervalSince1970: 4),
            accountID: "account-a"
        )

        #expect(store.notifications(
            forOriginalMessageID: "<first@example.org>",
            accountID: "account-a"
        ).isEmpty)
        #expect(store.notifications(
            forOriginalMessageID: "<second@example.org>",
            accountID: "account-a"
        ).map(\.finalRecipient) == ["second-updated@example.com"])
        #expect(store.notifications(
            forOriginalMessageID: "<third@example.org>",
            accountID: "account-a"
        ).map(\.finalRecipient) == ["third@example.com"])
    }
}
