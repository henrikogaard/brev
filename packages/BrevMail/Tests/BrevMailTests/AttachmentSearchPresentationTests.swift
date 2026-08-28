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

@Suite("AttachmentSearchPresentation")
struct AttachmentSearchPresentationTests {
    @Test("all attachments rows keep source folder and message routing context")
    func allAttachmentsRowsKeepSourceFolderAndMessageRoutingContext() {
        let source = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let header = Self.header(
            id: "message-1",
            folderID: "inbox",
            subject: "Q2 report",
            from: "finance@example.com",
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let attachment = Attachment(
            id: "attachment-1",
            name: "report.pdf",
            mimeType: "application/pdf",
            sizeBytes: 4096,
            resource: "cached://attachment-1"
        )

        let rows = AttachmentSearchPresentation.rows(
            records: [
                AttachmentSearchRecord(
                    sourceID: source,
                    sourceName: "Work",
                    header: header,
                    folderName: "Inbox",
                    attachment: attachment,
                    bodyCacheState: .cached,
                    contentIndexState: .indexed
                )
            ],
            filter: .allAttachments
        )

        #expect(rows.count == 1)
        #expect(rows[0].filename == "report.pdf")
        #expect(rows[0].subject == "Q2 report")
        #expect(rows[0].sender == "finance@example.com")
        #expect(rows[0].date == header.date)
        #expect(rows[0].sourceName == "Work")
        #expect(rows[0].folderName == "Inbox")
        #expect(rows[0].sizeBytes == 4096)
        #expect(rows[0].route == AttachmentSearchRoute(
            sourceID: source,
            folderID: "inbox",
            messageID: "message-1",
            attachmentID: "attachment-1"
        ))
    }

    @Test("attachment filters apply filename mime sender folder and query")
    func attachmentFiltersApplyFilenameMimeSenderFolderAndQuery() {
        let source = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let matching = AttachmentSearchRecord(
            sourceID: source,
            sourceName: "Legal",
            header: Self.header(
                id: "matching",
                folderID: "archive",
                subject: "Signed contract",
                from: "legal@example.com",
                date: Date(timeIntervalSince1970: 20)
            ),
            folderName: "Archive",
            attachment: Attachment(
                id: "contract",
                name: "contract.pdf",
                mimeType: "application/pdf",
                sizeBytes: 1200,
                resource: "cached://contract"
            ),
            bodyCacheState: .cached,
            contentIndexState: .indexed
        )
        let wrongType = AttachmentSearchRecord(
            sourceID: source,
            sourceName: "Legal",
            header: Self.header(
                id: "wrong-type",
                folderID: "archive",
                subject: "Signed contract",
                from: "legal@example.com",
                date: Date(timeIntervalSince1970: 10)
            ),
            folderName: "Archive",
            attachment: Attachment(
                id: "contract-docx",
                name: "contract.docx",
                mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                sizeBytes: 1200,
                resource: "cached://contract-docx"
            ),
            bodyCacheState: .cached,
            contentIndexState: .indexed
        )

        let rows = AttachmentSearchPresentation.rows(
            records: [wrongType, matching],
            filter: AttachmentSearchFilter(
                query: "contract",
                fileType: .pdf,
                sender: "legal@example.com",
                folderID: "archive",
                startDate: Date(timeIntervalSince1970: 15),
                endDate: Date(timeIntervalSince1970: 25)
            )
        )

        #expect(rows.map(\.attachmentID) == ["contract"])
    }

    @Test("attachment filters can match source labels and date windows")
    func attachmentFiltersCanMatchSourceLabelsAndDateWindows() {
        let source = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let matching = AttachmentSearchRecord(
            sourceID: source,
            sourceName: "Personal Archive",
            header: Self.header(
                id: "matching",
                folderID: "archive",
                subject: "Board packet",
                from: "board@example.com",
                date: Date(timeIntervalSince1970: 100)
            ),
            folderName: "Archive",
            attachment: Attachment(
                id: "packet",
                name: "packet.zip",
                mimeType: "application/zip",
                sizeBytes: 2048,
                resource: "cached://packet"
            ),
            bodyCacheState: .cached,
            contentIndexState: .unsupported
        )
        let tooOld = AttachmentSearchRecord(
            sourceID: source,
            sourceName: "Personal Archive",
            header: Self.header(
                id: "too-old",
                folderID: "archive",
                subject: "Board packet",
                from: "board@example.com",
                date: Date(timeIntervalSince1970: 50)
            ),
            folderName: "Archive",
            attachment: Attachment(
                id: "old-packet",
                name: "old-packet.zip",
                mimeType: "application/zip",
                sizeBytes: 2048,
                resource: "cached://old-packet"
            ),
            bodyCacheState: .cached,
            contentIndexState: .unsupported
        )

        let rows = AttachmentSearchPresentation.rows(
            records: [tooOld, matching],
            filter: AttachmentSearchFilter(
                query: "personal",
                startDate: Date(timeIntervalSince1970: 75),
                endDate: Date(timeIntervalSince1970: 125)
            )
        )

        #expect(rows.map(\.attachmentID) == ["packet"])
    }

    @Test("degraded states explain body cache and content index limits")
    func degradedStatesExplainBodyCacheAndContentIndexLimits() throws {
        let missingBody = AttachmentSearchRecord(
            sourceID: MailSourceID(accountID: "a", mailboxID: "m"),
            sourceName: "Personal",
            header: Self.header(
                id: "message-1",
                folderID: "inbox",
                subject: "Plans",
                from: "ada@example.com",
                date: Date()
            ),
            folderName: "Inbox",
            attachment: Attachment(
                id: "plans",
                name: "plans.pages",
                mimeType: "application/octet-stream",
                sizeBytes: 100,
                resource: nil
            ),
            bodyCacheState: .headerOnly,
            contentIndexState: .notIndexed
        )

        let row = try #require(AttachmentSearchPresentation.rows(
            records: [missingBody],
            filter: .allAttachments
        ).first)

        #expect(row.availability == .downloadRequired)
        #expect(row.degradedStateMessages.contains("Download required before preview or content indexing."))
        #expect(row.degradedStateMessages.contains("Attachment contents are not indexed."))
    }

    private static func header(
        id: String,
        folderID: String,
        subject: String,
        from: String,
        date: Date
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: Correspondent(email: from),
            to: [Correspondent(email: "me@example.com")],
            subject: subject,
            snippet: "",
            date: date,
            hasAttachments: true
        )
    }
}
