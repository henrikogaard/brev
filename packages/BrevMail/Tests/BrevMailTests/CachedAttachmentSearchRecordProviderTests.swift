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

private struct FakeEnumerator: CachedAttachmentEnumerating {
    let sources: [CachedAttachmentSource]
    func cachedMessagesWithBodies() async -> [CachedAttachmentSource] { sources }
}

private func makeHeader(id: String, folderID: String = "inbox") -> MessageHeader {
    MessageHeader(
        id: id,
        threadID: "t1",
        folderID: folderID,
        from: Correspondent(name: "Alex", email: "alex@example.org"),
        subject: "Hello",
        snippet: "Preview",
        date: Date(timeIntervalSince1970: 1_779_960_600),
        isAnswered: false,
        isForwarded: false
    )
}

@Suite("CachedAttachmentSearchRecordProvider")
struct CachedAttachmentSearchRecordProviderTests {
    @Test("yields one record per non-inline attachment, skipping inline parts")
    func yieldsNonInlineOnly() async throws {
        let pdf = Attachment(id: "att-pdf", name: "report.pdf", mimeType: "application/pdf", sizeBytes: 1024, isInline: false)
        let inlineImage = Attachment(id: "att-img", name: "logo.png", mimeType: "image/png", sizeBytes: 512, isInline: true)
        let source = CachedAttachmentSource(
            sourceID: MailSourceID(accountID: "acct-a", mailboxID: "mailbox-a"),
            sourceName: "Work",
            folderName: "Inbox",
            header: makeHeader(id: "m1"),
            body: MessageBody(messageID: "m1", attachments: [pdf, inlineImage])
        )
        let provider = CachedAttachmentSearchRecordProvider(enumerator: FakeEnumerator(sources: [source]))

        let records = await provider.attachmentRecords()

        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.attachment.id == "att-pdf")
        #expect(record.bodyCacheState == .cached)
        #expect(record.contentIndexState == .notIndexed)
        #expect(record.sourceID == MailSourceID(accountID: "acct-a", mailboxID: "mailbox-a"))
        #expect(record.sourceName == "Work")
        #expect(record.folderName == "Inbox")
        #expect(record.header.id == "m1")
    }

    @Test("yields no records for a message with only inline attachments")
    func yieldsNoneForInlineOnly() async {
        let inlineImage = Attachment(id: "att-img", name: "logo.png", mimeType: "image/png", sizeBytes: 512, isInline: true)
        let source = CachedAttachmentSource(
            sourceID: MailSourceID(accountID: "acct-a", mailboxID: "mailbox-a"),
            sourceName: "Work",
            folderName: "Inbox",
            header: makeHeader(id: "m1"),
            body: MessageBody(messageID: "m1", attachments: [inlineImage])
        )
        let provider = CachedAttachmentSearchRecordProvider(enumerator: FakeEnumerator(sources: [source]))

        let records = await provider.attachmentRecords()

        #expect(records.isEmpty)
    }

    @Test("flattens across multiple cached messages preserving order")
    func flattensAcrossMessages() async throws {
        let first = CachedAttachmentSource(
            sourceID: MailSourceID(accountID: "acct-a", mailboxID: "mailbox-a"),
            sourceName: "Work",
            folderName: "Inbox",
            header: makeHeader(id: "m1", folderID: "inbox"),
            body: MessageBody(messageID: "m1", attachments: [
                Attachment(id: "att-1", name: "a.pdf", mimeType: "application/pdf", sizeBytes: 1, isInline: false)
            ])
        )
        let second = CachedAttachmentSource(
            sourceID: MailSourceID(accountID: "acct-b", mailboxID: "mailbox-b"),
            sourceName: "Personal",
            folderName: "Archive",
            header: makeHeader(id: "m2", folderID: "archive"),
            body: MessageBody(messageID: "m2", attachments: [
                Attachment(id: "att-2", name: "b.pdf", mimeType: "application/pdf", sizeBytes: 2, isInline: false)
            ])
        )
        let provider = CachedAttachmentSearchRecordProvider(enumerator: FakeEnumerator(sources: [first, second]))

        let records = await provider.attachmentRecords()

        #expect(records.count == 2)
        #expect(records[0].attachment.id == "att-1")
        #expect(records[0].sourceName == "Work")
        #expect(records[0].folderName == "Inbox")
        #expect(records[0].sourceID == MailSourceID(accountID: "acct-a", mailboxID: "mailbox-a"))
        #expect(records[1].attachment.id == "att-2")
        #expect(records[1].sourceName == "Personal")
        #expect(records[1].folderName == "Archive")
        #expect(records[1].sourceID == MailSourceID(accountID: "acct-b", mailboxID: "mailbox-b"))
    }
}
