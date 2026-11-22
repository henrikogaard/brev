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

@Suite("Message list snooze wake candidates")
struct MessageListSnoozeWakeCandidateTests {
    @Test("expired cached Inbox members load from cached headers on reopen")
    @MainActor
    func expiredCachedInboxMemberLoadsOnReopen() async throws {
        let backend = MockBackend()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let sent = Folder(id: "Sent", name: "Sent", role: .custom)
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: "mailbox")
        let wakeAt = Date(timeIntervalSince1970: 1_800_000_000)
        let firstPage = Self.header(
            id: "newest",
            folderID: inbox.id,
            messageID: "newest@example.org",
            date: wakeAt.addingTimeInterval(-60)
        )
        let oldInboxMessage = Self.header(
            id: "old",
            folderID: inbox.id,
            messageID: "reply@example.org",
            inReplyTo: "anchor@example.org",
            date: wakeAt.addingTimeInterval(-86400)
        )
        let anchor = Self.header(
            id: "anchor",
            folderID: sent.id,
            messageID: "anchor@example.org",
            date: wakeAt.addingTimeInterval(-172_800)
        )
        backend.cachedMessageHeadersHandler = { folder, _ in
            folder.id == inbox.id ? [firstPage, oldInboxMessage] : [anchor]
        }
        let snooze = LocalMessageSnooze(
            messageID: SourceMessageID(sourceID: sourceID, messageID: anchor.id),
            wakeAt: wakeAt,
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example.org"])
        )

        let candidates = try await LocalMessageWorkflowConversationCache.loadExpiredInboxWakeCandidates(
            backend: backend,
            sourceID: sourceID,
            inboxFolder: inbox,
            folders: [inbox, sent],
            loadedHeaders: [firstPage],
            snoozes: [snooze],
            now: wakeAt,
            isEligible: true,
            isCurrent: { true }
        )

        #expect(candidates == [oldInboxMessage])
        #expect(candidates.first?.date == oldInboxMessage.date)
    }

    @Test("ineligible inbox context does not read the cached headers")
    @MainActor
    func ineligibleContextDoesNotReadCache() async throws {
        let backend = MockBackend()
        backend.cachedMessageHeadersHandler = { _, _ in
            throw CancellationError()
        }
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)

        let candidates = try await LocalMessageWorkflowConversationCache.loadExpiredInboxWakeCandidates(
            backend: backend,
            sourceID: sourceID,
            inboxFolder: inbox,
            folders: [inbox],
            loadedHeaders: [],
            snoozes: [],
            now: Date(),
            isEligible: false,
            isCurrent: { true }
        )

        #expect(candidates.isEmpty)
    }

    @Test("empty, future-only, and other-source snoozes do not read cached headers")
    @MainActor
    func noExpiredSourceOwnedSnoozeDoesNotReadCache() async throws {
        let backend = MockBackend()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let sourceA = MailSourceID(accountID: backend.account.id, mailboxID: "mailbox-a")
        let sourceB = MailSourceID(accountID: backend.account.id, mailboxID: "mailbox-b")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let readCounter = CachedHeaderReadCounter()
        backend.cachedMessageHeadersHandler = { _, _ in
            readCounter.recordRead()
            return []
        }
        let scenarios = [
            [LocalMessageSnooze](),
            [LocalMessageSnooze(
                messageID: SourceMessageID(sourceID: sourceA, messageID: "future"),
                wakeAt: now.addingTimeInterval(60)
            )],
            [LocalMessageSnooze(
                messageID: SourceMessageID(sourceID: sourceB, messageID: "other-source"),
                wakeAt: now.addingTimeInterval(-60)
            )],
        ]

        for snoozes in scenarios {
            let candidates = try await LocalMessageWorkflowConversationCache.loadExpiredInboxWakeCandidates(
                backend: backend,
                sourceID: sourceA,
                inboxFolder: inbox,
                folders: [inbox],
                loadedHeaders: [],
                snoozes: snoozes,
                now: now,
                isEligible: true,
                isCurrent: { true }
            )
            #expect(candidates.isEmpty)
            #expect(readCounter.readCount == 0)
        }
    }

    private static func header(
        id: String,
        folderID: String,
        messageID: String,
        inReplyTo: String? = nil,
        date: Date
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "same-thread",
            folderID: folderID,
            from: Correspondent(email: "ada@example.org"),
            to: [],
            subject: "Wake candidate",
            snippet: "",
            date: date,
            messageID: messageID,
            inReplyTo: inReplyTo
        )
    }
}

private final class CachedHeaderReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func recordRead() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
