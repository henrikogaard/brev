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

#if os(macOS)
import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("Mail Context column state")
struct MailContextColumnStateTests {
    @Test("selected message defaults chat to its sender")
    func selectedMessageDefaultsChatToSender() {
        let selected = Self.header(senderEmail: "ada@example.com")

        let scope = MailContextColumnScopePolicy.chatScope(
            selectedHeader: selected,
            focusedFolder: Self.inbox
        )

        #expect(scope == .sender(email: "ada@example.com"))
    }

    @Test("no selection defaults chat to the focused folder")
    func noSelectionDefaultsChatToFocusedFolder() {
        let scope = MailContextColumnScopePolicy.chatScope(
            selectedHeader: nil,
            focusedFolder: Self.inbox
        )

        #expect(scope == .folder)
    }

    @Test("clearing selection does not retain the previous sender")
    func clearingSelectionDoesNotRetainPreviousSender() {
        let selected = Self.header(senderEmail: "ada@example.com")
        #expect(
            MailContextColumnScopePolicy.chatScope(
                selectedHeader: selected,
                focusedFolder: Self.inbox
            ) == .sender(email: "ada@example.com")
        )

        #expect(
            MailContextColumnScopePolicy.chatScope(
                selectedHeader: nil,
                focusedFolder: Self.inbox
            ) == .folder
        )
    }

    @Test("no selection and no folder falls back to account chat")
    func noSelectionAndNoFolderFallsBackToAccountChat() {
        let scope = MailContextColumnScopePolicy.chatScope(
            selectedHeader: nil,
            focusedFolder: nil
        )

        #expect(scope == .account)
    }

    @Test("sender context keys normalize email within a mailbox")
    func senderContextKeysNormalizeEmailWithinMailbox() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")

        #expect(
            SenderContextCacheKey(sourceID: sourceID, senderEmail: " Ada@Example.COM ")
                == SenderContextCacheKey(sourceID: sourceID, senderEmail: "ada@example.com")
        )
    }

    @Test("sender context cache expires old entries and stays bounded")
    func senderContextCacheExpiresAndEvicts() async {
        let cache = SenderContextSnapshotCache(capacity: 1, timeToLive: 30)
        let firstKey = SenderContextCacheKey(
            sourceID: MailSourceID(accountID: "account", mailboxID: "primary"),
            senderEmail: "first@example.com"
        )
        let secondKey = SenderContextCacheKey(
            sourceID: MailSourceID(accountID: "account", mailboxID: "primary"),
            senderEmail: "second@example.com"
        )
        let first = Self.snapshot(email: "first@example.com")
        let second = Self.snapshot(email: "second@example.com")
        let start = Date(timeIntervalSince1970: 1000)

        await cache.insert(first, for: firstKey, now: start)
        #expect(await cache.value(for: firstKey, now: start.addingTimeInterval(29)) == first)
        #expect(await cache.value(for: firstKey, now: start.addingTimeInterval(31)) == nil)

        await cache.insert(first, for: firstKey, now: start)
        await cache.insert(second, for: secondKey, now: start)
        #expect(await cache.value(for: firstKey, now: start) == nil)
        #expect(await cache.value(for: secondKey, now: start) == second)
    }

    @Test("sender history waits briefly so the reading pane wins selection work")
    func senderHistoryUsesShortDebounce() {
        #expect(MailContextSenderLoadPolicy.debounceNanoseconds > 0)
        #expect(MailContextSenderLoadPolicy.debounceNanoseconds <= 500_000_000)
    }

    @Test("resizable panels preserve both minimum heights")
    func resizablePanelsPreserveBothMinimumHeights() {
        let availableHeight: CGFloat = 800

        #expect(
            MailContextPanelSplitPolicy.senderHeight(
                preferred: 40,
                available: availableHeight
            ) == MailContextPanelSplitPolicy.senderMinimumHeight
        )
        #expect(
            MailContextPanelSplitPolicy.senderHeight(
                preferred: 900,
                available: availableHeight
            ) == availableHeight - MailContextPanelSplitPolicy.chatMinimumHeight
        )
    }

    @Test("resizable panels share short inspector space without collapsing")
    func resizablePanelsShareShortInspectorSpace() {
        let availableHeight: CGFloat = 300

        #expect(
            MailContextPanelSplitPolicy.senderHeight(
                preferred: MailContextPanelSplitPolicy.defaultSenderHeight,
                available: availableHeight
            ) == availableHeight / 2
        )
    }

    @Test("resizing starts from the visible clamped divider height")
    func resizablePanelsStartDraggingFromVisibleHeight() {
        #expect(
            MailContextPanelSplitPolicy.dragStartHeight(
                preferred: 800,
                available: 500
            ) == 280
        )
    }

    @Test("empty state is reachable when sender search returns no headers")
    func emptyStateWhenSearchReturnsNoHeaders() {
        let selected = MessageHeader(
            id: "selected",
            threadID: "thread-selected",
            folderID: "archive",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            subject: "Selected",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 86400)
        )
        let snapshot = SenderContextSnapshot(
            identity: SenderContextIdentity(
                email: "ada@example.com",
                displayName: "Ada Lovelace",
                contactDisplayName: "Ada"
            ),
            messageCount: 0,
            firstSeen: nil,
            lastSeen: nil,
            recent: []
        )

        let state = SenderContextPanelStatePolicy.state(
            for: selected,
            result: .success(snapshot)
        )

        #expect(state == .empty(selected))
    }

    private static let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

    private static func snapshot(email: String) -> SenderContextSnapshot {
        SenderContextSnapshot(
            identity: SenderContextIdentity(email: email, displayName: email, contactDisplayName: nil),
            messageCount: 1,
            firstSeen: Date(timeIntervalSince1970: 1),
            lastSeen: Date(timeIntervalSince1970: 1),
            recent: []
        )
    }

    private static func header(senderEmail: String) -> MessageHeader {
        MessageHeader(
            id: "selected",
            threadID: "thread-selected",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: senderEmail),
            subject: "Selected",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 86400)
        )
    }
}
#endif
