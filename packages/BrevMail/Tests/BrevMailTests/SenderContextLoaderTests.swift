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

@Suite("Sender context loader")
struct SenderContextLoaderTests {
    @Test("sender search uses the local index without broadening beyond the sender")
    func senderSearchUsesTextAndFromScope() {
        #expect(
            SenderContextLoader.senderSearchQuery(for: "ada@example.com")
                == SearchQuery(
                    text: "ada@example.com",
                    from: "ada@example.com",
                    execution: .cacheOnly
                )
        )
    }

    @Test("load builds sender snapshot from cache-only source search")
    func loadBuildsSenderSnapshotFromCacheOnlySourceSearch() async throws {
        let account = Self.account(id: "acct-1")
        let mailbox = Mailbox(
            id: "primary",
            email: "owner@example.com",
            displayName: "Owner",
            isPrimary: true
        )
        let sourceID = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "archive", name: "Archive", role: .archive),
            Folder(id: "sent", name: "Sent", role: .sent),
        ]
        let selected = Self.header(
            id: "selected",
            folderID: "archive",
            fromName: "Ada Lovelace",
            fromEmail: "ada@example.com",
            subject: "Selected",
            day: 4
        )
        let backend = MockBackend(
            account: account,
            folders: folders,
            messagesByFolder: [
                "inbox": [
                    Self.header(
                        id: "inbox-1",
                        folderID: "inbox",
                        fromName: "Ada Lovelace",
                        fromEmail: "ada@example.com",
                        subject: "Newest",
                        day: 5
                    ),
                    Self.header(
                        id: "inbox-2",
                        folderID: "inbox",
                        fromName: "Other Sender",
                        fromEmail: "other@example.com",
                        subject: "Ignore me",
                        day: 6
                    ),
                ],
                "archive": [
                    selected,
                    Self.header(
                        id: "archive-1",
                        folderID: "archive",
                        fromName: "Ada Lovelace",
                        fromEmail: "ada@example.com",
                        subject: "Older",
                        day: 2
                    ),
                ],
                "sent": [
                    Self.header(
                        id: "sent-1",
                        folderID: "sent",
                        fromName: "Ada Lovelace",
                        fromEmail: "ada@example.com",
                        subject: "Sent copy",
                        day: 3
                    ),
                ],
            ],
            mailboxes: [mailbox],
            contacts: [
                ContactLookupResult(
                    id: "contact-ada",
                    displayName: "Ada",
                    email: "ada@example.com",
                    sourceID: sourceID
                ),
            ]
        )

        let loader = SenderContextLoader(
            folderNameByID: Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })
        )

        let result = await loader.load(
            selected: selected,
            sourceID: sourceID,
            backend: backend
        )

        let snapshot = try result.get()
        #expect(snapshot.identity.email == "ada@example.com")
        #expect(snapshot.identity.displayName == "Ada Lovelace")
        #expect(snapshot.identity.contactDisplayName == "Ada")
        #expect(snapshot.messageCount == 4)
        #expect(snapshot.firstSeen == Self.date(day: 2))
        #expect(snapshot.lastSeen == Self.date(day: 5))
        #expect(snapshot.recent.map { $0.id } == ["inbox-1", "selected", "sent-1", "archive-1"])
        #expect(snapshot.recent.map { $0.folderName } == ["Inbox", "Archive", "Sent", "Archive"])
        #expect(snapshot.recent.allSatisfy { $0.sourceID == sourceID })
    }

    @Test("load succeeds without contact lookup or folder aliases")
    func loadSucceedsWithoutContactLookupOrFolderAliases() async throws {
        let selected = Self.header(
            id: "selected",
            folderID: "inbox",
            fromName: "Grace Hopper",
            fromEmail: "grace@example.com",
            subject: "Selected",
            day: 4
        )
        let backend = MockBackend(
            account: Self.account(id: "acct-2"),
            folders: [Folder(id: "inbox", name: "Inbox", role: .inbox)],
            messagesByFolder: [
                "inbox": [
                    selected,
                    Self.header(
                        id: "older",
                        folderID: "inbox",
                        fromName: "Grace Hopper",
                        fromEmail: "grace@example.com",
                        subject: "Older",
                        day: 1
                    ),
                ],
            ],
            contacts: []
        )

        let result = await SenderContextLoader().load(
            selected: selected,
            sourceID: nil,
            backend: backend
        )

        let snapshot = try result.get()
        #expect(snapshot.identity.contactDisplayName == nil)
        #expect(snapshot.messageCount == 2)
        #expect(snapshot.recent.map { $0.folderName } == [nil, nil])
        #expect(snapshot.recent.allSatisfy { $0.sourceID == nil })
    }

    private static func account(id: String) -> BrevAccount {
        BrevAccount(
            id: id,
            displayName: "Account \(id)",
            emailAddress: "\(id)@example.com",
            backendIdentifier: BrevAccount.imapSMTPBackendIdentifier,
            backendDisplayName: BrevAccount.imapSMTPBackendDisplayName
        )
    }

    private static func header(
        id: String,
        folderID: String,
        fromName: String,
        fromEmail: String,
        subject: String,
        day: Int
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: Correspondent(name: fromName, email: fromEmail),
            subject: subject,
            snippet: "Snippet \(id)",
            date: date(day: day)
        )
    }

    private static func date(day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86400))
    }
}
