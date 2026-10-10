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

/// iOS Mail parity for the phone message list: swipe ordering and the shorter
/// long-press menu (audit findings L6 and L7).
@Suite("MessageCommandPresentation compact layout")
struct MessageCommandCompactLayoutTests {
    @Test("compact leading swipe is a single read toggle that a full swipe performs")
    func compactLeadingSwipeIsReadToggle() {
        #expect(MessageCommandPresentation.leadingSwipeActions(isCompact: true) == [.toggleRead])
        #expect(MessageCommandPresentation.leadingSwipeActions(isCompact: false) == [.toggleFlag, .toggleRead])
    }

    @Test("compact trailing swipe lists the full-swipe action first, then Flag, then More")
    func compactTrailingSwipeOrder() {
        // SwiftUI places the first trailing action at the screen edge and runs it on
        // a full swipe, so iOS Mail's visual More | Flag | Archive is declared reversed.
        #expect(MessageCommandPresentation.trailingSwipeActions(hasArchive: true, isCompact: true)
            == [.archive, .toggleFlag, .more])
        #expect(MessageCommandPresentation.trailingSwipeActions(hasArchive: false, isCompact: true)
            == [.delete, .toggleFlag, .more])
        #expect(MessageCommandPresentation.trailingSwipeActions(hasArchive: true, isCompact: false)
            == [.archive, .delete])
    }

    @Test("More offers response, snooze, move and junk actions that exist in the context menu")
    func swipeMoreActionsAreContextMenuActions() {
        let withArchive = MessageCommandPresentation.swipeMoreActions(hasArchive: true)
        #expect(withArchive == [.reply, .replyAll, .forward, .toggleSnooze, .move, .setJunk, .delete])
        let withoutArchive = MessageCommandPresentation.swipeMoreActions(hasArchive: false)
        #expect(withoutArchive == [.reply, .replyAll, .forward, .toggleSnooze, .move, .setJunk])

        let menu = Self.menu(layout: .full)
        for action in withArchive {
            #expect(menu.action(action) != nil, "\(action) must be a real context-menu action")
        }
    }

    @Test("compact context menu leads with reply, mark and filing, and folds the rest under More")
    func compactMenuSections() {
        let menu = Self.menu(layout: .compact)
        #expect(menu.sections.map { $0.actions.map(\.action) } == [
            [.reply, .replyAll, .forward],
            [.toggleRead, .toggleFlag, .toggleSnooze],
            [.move, .archive, .delete],
            [.select]
        ])
        let overflow = menu.overflowSections.flatMap { $0.actions.map(\.action) }
        #expect(overflow.contains(.pinToTop))
        #expect(overflow.contains(.toggleDone))
        #expect(overflow.contains(.createTask))
        #expect(overflow.contains(.properties))
        #expect(overflow.contains(.setJunk))
    }

    @Test("compact layout neither drops nor duplicates an action")
    func compactLayoutKeepsEveryAction() {
        let full = Self.menu(layout: .full)
        let compact = Self.menu(layout: .compact)
        let fullActions = full.sections.flatMap { $0.actions.map(\.action) }
        let compactActions = (compact.sections + compact.overflowSections).flatMap { $0.actions.map(\.action) }
        #expect(Set(fullActions) == Set(compactActions))
        #expect(fullActions.count == compactActions.count)
        #expect(compact.sections.flatMap(\.actions).count <= 11)
    }

    @Test("compact layout keeps enablement and destructive roles")
    func compactLayoutKeepsPresentationDetails() {
        let compact = Self.menu(layout: .compact, canReply: false)
        #expect(compact.action(.reply)?.isEnabled == false)
        #expect(compact.action(.delete)?.role == .destructive)
        #expect(compact.action(.blockSender)?.role == .destructive)
    }

    @Test("full layout has no overflow section")
    func fullLayoutHasNoOverflow() {
        #expect(Self.menu(layout: .full).overflowSections.isEmpty)
    }

    private static func menu(
        layout: MessageContextMenuLayout,
        canReply: Bool = true
    ) -> MessageContextMenuPresentation {
        MessageCommandPresentation.contextMenu(
            for: MessageHeader(
                id: "m1",
                threadID: "t1",
                folderID: "inbox",
                from: Correspondent(name: "Alex", email: "alex@example.org"),
                subject: "Hello",
                snippet: "Preview",
                date: Date(timeIntervalSince1970: 1_779_960_600),
                isRead: false,
                isFlagged: false
            ),
            isSelected: false,
            isPinned: false,
            isSnoozed: false,
            isDone: false,
            canOpenInNewWindow: false,
            canArchive: true,
            canMove: true,
            junkActionTitle: "Report Junk",
            canBlockSender: true,
            canDelete: true,
            canReply: canReply,
            canShowProperties: true,
            layout: layout
        )
    }
}
