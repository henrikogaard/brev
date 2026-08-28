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

@Suite("SenderContextModel")
struct SenderContextModelTests {
    @Test("builder uses selected sender identity and contact name")
    func builderUsesSelectedSenderIdentityAndContactName() {
        let selected = Self.makeHeader(
            id: "selected",
            fromName: "Ada Lovelace",
            fromEmail: "ada@example.com",
            subject: "Selected",
            date: Self.date(day: 5)
        )

        let snapshot = SenderContextSnapshotBuilder.make(
            from: selected,
            matchingHeaders: [selected],
            contactDisplayName: "Ada",
            folderNameByID: [:]
        )

        #expect(
            snapshot.identity == SenderContextIdentity(
                email: "ada@example.com",
                displayName: "Ada Lovelace",
                contactDisplayName: "Ada"
            )
        )
    }

    @Test("builder sorts recent headers by date, caps to eight, and normalizes blank subjects")
    func builderSortsCapsAndNormalizesRecentItems() {
        let selected = Self.makeHeader(
            id: "selected",
            fromName: "Ada Lovelace",
            fromEmail: "ada@example.com",
            subject: "Selected",
            date: Self.date(day: 10),
            folderID: "archive"
        )
        let olderBlank = Self.makeHeader(
            id: "m-1",
            fromName: "Ada Lovelace",
            fromEmail: "ada@example.com",
            subject: "   ",
            date: Self.date(day: 1),
            folderID: "archive"
        )
        let newest = Self.makeHeader(
            id: "m-9",
            fromName: "Ada Lovelace",
            fromEmail: "ada@example.com",
            subject: "Newest",
            date: Self.date(day: 9),
            folderID: "inbox"
        )
        let middle = Self.makeHeader(
            id: "m-5",
            fromName: "Ada Lovelace",
            fromEmail: "ada@example.com",
            subject: "Middle",
            date: Self.date(day: 5),
            folderID: "sent"
        )
        let headers = [
            olderBlank,
            Self.makeHeader(
                id: "m-2",
                fromName: "Ada Lovelace",
                fromEmail: "ada@example.com",
                subject: "Two",
                date: Self.date(day: 2),
                folderID: "inbox"
            ),
            Self.makeHeader(
                id: "m-3",
                fromName: "Ada Lovelace",
                fromEmail: "ada@example.com",
                subject: "Three",
                date: Self.date(day: 3),
                folderID: "inbox"
            ),
            Self.makeHeader(
                id: "m-4",
                fromName: "Ada Lovelace",
                fromEmail: "ada@example.com",
                subject: "Four",
                date: Self.date(day: 4),
                folderID: "archive"
            ),
            middle,
            Self.makeHeader(
                id: "m-6",
                fromName: "Ada Lovelace",
                fromEmail: "ada@example.com",
                subject: "Six",
                date: Self.date(day: 6),
                folderID: "sent"
            ),
            Self.makeHeader(
                id: "m-7",
                fromName: "Ada Lovelace",
                fromEmail: "ada@example.com",
                subject: "Seven",
                date: Self.date(day: 7),
                folderID: "drafts"
            ),
            Self.makeHeader(
                id: "m-8",
                fromName: "Ada Lovelace",
                fromEmail: "ada@example.com",
                subject: "Eight",
                date: Self.date(day: 8),
                folderID: "drafts"
            ),
            newest,
            selected,
        ]

        let snapshot = SenderContextSnapshotBuilder.make(
            from: selected,
            matchingHeaders: headers,
            contactDisplayName: nil,
            folderNameByID: [
                "archive": "Archive",
                "drafts": "Drafts",
                "inbox": "Inbox",
                "sent": "Sent",
            ]
        )

        #expect(snapshot.recent.count == 8)
        #expect(
            snapshot.recent.map(\.id) == [
                "selected",
                "m-9",
                "m-8",
                "m-7",
                "m-6",
                "m-5",
                "m-4",
                "m-3",
            ]
        )
        #expect(snapshot.recent[0].folderName == "Archive")
        #expect(snapshot.recent[1].folderName == "Inbox")
        #expect(snapshot.recent[4].folderName == "Sent")
        #expect(snapshot.recent.allSatisfy { $0.sourceID == nil })

        let blankSubjectSnapshot = SenderContextSnapshotBuilder.make(
            from: selected,
            matchingHeaders: [olderBlank],
            contactDisplayName: nil,
            folderNameByID: ["archive": "Archive"]
        )
        #expect(blankSubjectSnapshot.recent.map(\.subject) == ["(no subject)"])
    }

    @Test("builder computes count and seen range from the full matching set")
    func builderComputesCountAndSeenRangeFromFullMatchingSet() {
        let selected = Self.makeHeader(
            id: "selected",
            fromName: "Ada Lovelace",
            fromEmail: "ada@example.com",
            subject: "Selected",
            date: Self.date(day: 10)
        )
        let headers = (1 ... 10).map { day in
            Self.makeHeader(
                id: "m-\(day)",
                fromName: "Ada Lovelace",
                fromEmail: "ada@example.com",
                subject: "Message \(day)",
                date: Self.date(day: day)
            )
        } + [selected]

        let snapshot = SenderContextSnapshotBuilder.make(
            from: selected,
            matchingHeaders: headers,
            contactDisplayName: nil,
            folderNameByID: [:]
        )

        #expect(snapshot.messageCount == 11)
        #expect(snapshot.firstSeen == Self.date(day: 1))
        #expect(snapshot.lastSeen == Self.date(day: 10))
    }

    private static func makeHeader(
        id: String,
        fromName: String,
        fromEmail: String,
        subject: String,
        date: Date,
        folderID: String = "inbox"
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: Correspondent(name: fromName, email: fromEmail),
            subject: subject,
            snippet: "Preview for \(id)",
            date: date
        )
    }

    private static func date(day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86400))
    }
}
