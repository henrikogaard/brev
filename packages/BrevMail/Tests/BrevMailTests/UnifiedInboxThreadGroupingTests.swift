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

@Suite("UnifiedInboxThreadGrouping")
struct UnifiedInboxThreadGroupingTests {
    private static let source = MailSourceID(accountID: "acct-1", mailboxID: "personal")
    private static let otherSource = MailSourceID(accountID: "acct-2", mailboxID: "work")

    @Test("thread identity is scoped to the source, not the thread id alone")
    func threadIdentityIsScopedToSource() {
        let mine = Self.item(id: "a", threadID: "t1", sourceID: Self.source)
        let theirs = Self.item(id: "b", threadID: "t1", sourceID: Self.otherSource)

        #expect(UnifiedInboxThreadGrouping.key(for: mine) != UnifiedInboxThreadGrouping.key(for: theirs))
    }

    @Test("counts tally each source thread and ignore unthreaded sources")
    func countsTallyThreadedSourcesOnly() {
        let items = [
            Self.item(id: "a", threadID: "t1", sourceID: Self.source),
            Self.item(id: "b", threadID: "t1", sourceID: Self.source),
            Self.item(id: "c", threadID: "t9", sourceID: Self.otherSource),
            Self.item(id: "d", threadID: "t9", sourceID: Self.otherSource)
        ]

        let counts = UnifiedInboxThreadGrouping.counts(for: items) { $0 == Self.source }

        #expect(counts[UnifiedInboxThreadGrouping.key(for: items[0])] == 2)
        #expect(counts[UnifiedInboxThreadGrouping.key(for: items[2])] == nil)
    }

    @Test("parents keep the first item of each thread and drop the rest")
    func parentsKeepFirstItemPerThread() {
        let items = [
            Self.item(id: "newest", threadID: "t1", sourceID: Self.source),
            Self.item(id: "other", threadID: "t2", sourceID: Self.source),
            Self.item(id: "older", threadID: "t1", sourceID: Self.source)
        ]
        let counts = UnifiedInboxThreadGrouping.counts(for: items) { _ in true }

        let parents = UnifiedInboxThreadGrouping.parents(from: items, counts: counts)

        #expect(parents.map(\.header.id) == ["newest", "other"])
    }

    @Test("single-message threads are never collapsed away")
    func singleMessageThreadsSurvive() {
        let items = [
            Self.item(id: "a", threadID: "t1", sourceID: Self.source),
            Self.item(id: "b", threadID: "t2", sourceID: Self.source)
        ]
        let counts = UnifiedInboxThreadGrouping.counts(for: items) { _ in true }

        let parents = UnifiedInboxThreadGrouping.parents(from: items, counts: counts)

        #expect(parents.map(\.header.id) == ["a", "b"])
    }

    @Test("children exclude the parent and sort oldest first")
    func childrenExcludeParentSortedOldestFirst() {
        let newest = Self.item(id: "newest", threadID: "t1", sourceID: Self.source, date: Date(timeIntervalSince1970: 300))
        let middle = Self.item(id: "middle", threadID: "t1", sourceID: Self.source, date: Date(timeIntervalSince1970: 200))
        let oldest = Self.item(id: "oldest", threadID: "t1", sourceID: Self.source, date: Date(timeIntervalSince1970: 100))
        let unrelated = Self.item(id: "unrelated", threadID: "t2", sourceID: Self.source)

        let children = UnifiedInboxThreadGrouping.children(
            for: UnifiedInboxThreadGrouping.key(for: newest),
            excludingParentID: newest.id,
            from: [newest, unrelated, oldest, middle]
        )

        #expect(children.map(\.header.id) == ["oldest", "middle"])
    }

    private static func item(
        id: String,
        threadID: String,
        sourceID: MailSourceID,
        date: Date = Date(timeIntervalSince1970: 0)
    ) -> UnifiedInboxItem {
        UnifiedInboxItem(
            sourceID: sourceID,
            folder: Folder(id: "inbox", name: "Inbox", role: .inbox),
            header: MessageHeader(
                id: id,
                threadID: threadID,
                folderID: "inbox",
                from: Correspondent(name: "Ada", email: "ada@example.org"),
                subject: "Subject",
                snippet: "",
                date: date,
                isRead: false
            ),
            sourceTitle: "Mailbox",
            sourceSubtitle: "mailbox@example.org",
            archiveFolder: nil
        )
    }
}
