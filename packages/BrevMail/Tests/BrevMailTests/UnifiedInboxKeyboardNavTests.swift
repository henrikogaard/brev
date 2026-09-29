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

@Suite("Unified inbox keyboard navigation sequence")
struct UnifiedInboxKeyboardNavTests {
    @Test("expanded thread children splice in after their parent")
    func expandedThreadChildrenInterleave() {
        let source = MailSourceID(accountID: "account", mailboxID: "inbox")
        let solo = Self.item(id: "solo", threadID: "t-solo", sourceID: source)
        let parent = Self.item(id: "parent", threadID: "t-parent", sourceID: source)
        let child = Self.item(id: "child", threadID: "t-parent", sourceID: source)
        let tail = Self.item(id: "tail", threadID: "t-tail", sourceID: source)

        let sequence = UnifiedInboxListView.keyboardNavigableSequence(
            parents: [solo, parent, tail],
            itemsByThreadKey: [UnifiedInboxThreadGrouping.key(for: parent): [parent, child]],
            expandedThreadKeys: [UnifiedInboxThreadGrouping.key(for: parent)]
        )

        #expect(sequence.map(\.id) == [solo.id, parent.id, child.id, tail.id])
    }

    @Test("collapsed threads contribute only their parent row")
    func collapsedThreadsSkipChildren() {
        let source = MailSourceID(accountID: "account", mailboxID: "inbox")
        let parent = Self.item(id: "parent", threadID: "t-parent", sourceID: source)
        let child = Self.item(id: "child", threadID: "t-parent", sourceID: source)

        let sequence = UnifiedInboxListView.keyboardNavigableSequence(
            parents: [parent],
            itemsByThreadKey: [UnifiedInboxThreadGrouping.key(for: parent): [parent, child]],
            expandedThreadKeys: []
        )

        #expect(sequence.map(\.id) == [parent.id])
    }

    @Test("the parent row itself is never duplicated by its thread bucket")
    func parentIsNotDuplicatedFromThreadBucket() {
        let source = MailSourceID(accountID: "account", mailboxID: "inbox")
        let parent = Self.item(id: "parent", threadID: "t-parent", sourceID: source)

        let sequence = UnifiedInboxListView.keyboardNavigableSequence(
            parents: [parent],
            itemsByThreadKey: [UnifiedInboxThreadGrouping.key(for: parent): [parent]],
            expandedThreadKeys: [UnifiedInboxThreadGrouping.key(for: parent)]
        )

        #expect(sequence.map(\.id) == [parent.id])
    }

    private static func item(
        id: String,
        threadID: String,
        sourceID: MailSourceID
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
                date: Date(timeIntervalSince1970: 0),
                isRead: false
            ),
            sourceTitle: "Mailbox",
            sourceSubtitle: "mailbox@example.org",
            archiveFolder: nil
        )
    }
}
