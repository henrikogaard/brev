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

#if canImport(UIKit)
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// iOS-only snapshot coverage for the All Attachments surface: the populated
/// list, the empty state, and a degraded (download-required, not-indexed) row.
///
/// Baselines are recorded later on a simulator; on macOS this file compiles
/// out entirely because UIKit is unavailable.
@Suite("All Attachments snapshots")
@MainActor
struct AllAttachmentsViewSnapshotTests {
    private static let theme = BrevTheme.brevBuiltIns.first!

    @Test("Populated attachment list renders")
    func populated() throws {
        try assert(records: Self.populatedRecords, named: "populated")
    }

    @Test("Empty attachment list renders the empty state")
    func emptyState() throws {
        try assert(records: [], named: "emptyState")
    }

    @Test("Degraded attachment renders the download-required badge")
    func degraded() throws {
        try assert(records: [Self.degradedRecord], named: "degraded")
    }

    @Test("Query-filtered list narrows to matching attachments")
    func queryFiltered() throws {
        try assert(
            records: Self.populatedRecords,
            filter: AttachmentSearchFilter(query: "report"),
            named: "queryFiltered"
        )
    }

    private func assert(
        records: [AttachmentSearchRecord],
        filter: AttachmentSearchFilter = .allAttachments,
        named: String
    ) throws {
        let theme = Self.theme
        let view = AllAttachmentsView(
            previewRecords: records,
            navigation: MailNavigationState(),
            filter: filter,
            onOpen: { _ in }
        )
        .frame(width: 390, height: 700)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: named
        )
    }

    private static let source = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")

    private static var populatedRecords: [AttachmentSearchRecord] {
        [
            AttachmentSearchRecord(
                sourceID: source,
                sourceName: "Personal",
                header: header(
                    id: "message-1",
                    folderID: "inbox",
                    subject: "Q2 report",
                    from: "finance@example.com",
                    date: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                folderName: "Inbox",
                attachment: Attachment(
                    id: "attachment-1",
                    name: "report.pdf",
                    mimeType: "application/pdf",
                    sizeBytes: 4096,
                    resource: "cached://attachment-1"
                ),
                bodyCacheState: .cached,
                contentIndexState: .indexed
            ),
            AttachmentSearchRecord(
                sourceID: source,
                sourceName: "Personal",
                header: header(
                    id: "message-2",
                    folderID: "inbox",
                    subject: "Launch photos",
                    from: "design@example.com",
                    date: Date(timeIntervalSince1970: 1_799_000_000)
                ),
                folderName: "Inbox",
                attachment: Attachment(
                    id: "attachment-2",
                    name: "hero.png",
                    mimeType: "image/png",
                    sizeBytes: 8192,
                    resource: "cached://attachment-2"
                ),
                bodyCacheState: .cached,
                contentIndexState: .indexed
            ),
            AttachmentSearchRecord(
                sourceID: source,
                sourceName: "Personal",
                header: header(
                    id: "message-3",
                    folderID: "archive",
                    subject: "Signed contract",
                    from: "legal@example.com",
                    date: Date(timeIntervalSince1970: 1_798_000_000)
                ),
                folderName: "Archive",
                attachment: Attachment(
                    id: "attachment-3",
                    name: "contract.docx",
                    mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    sizeBytes: 2048,
                    resource: "cached://attachment-3"
                ),
                bodyCacheState: .cached,
                contentIndexState: .indexed
            )
        ]
    }

    private static var degradedRecord: AttachmentSearchRecord {
        AttachmentSearchRecord(
            sourceID: source,
            sourceName: "Personal",
            header: header(
                id: "message-9",
                folderID: "inbox",
                subject: "Plans",
                from: "ada@example.com",
                date: Date(timeIntervalSince1970: 1_797_000_000)
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
#endif
