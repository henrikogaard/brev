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
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// Snapshot baselines for the core per-row and empty-state surfaces of
/// BrevMail. Each test case is data-static — no async backend calls are
/// made — and records its reference image under `__Snapshots__/` on
/// first run (set `SNAPSHOT_TESTING_RECORD=true` to re-record).
///
/// The six cases covered here are:
///   1. Message list row — unread
///   2. Message list row — flagged + read
///   3. Message list row — with attachment indicator
///   4. Folder sidebar entry — inbox with unread count badge
///   5. Folder sidebar entry — no unread (no badge)
///   6. Empty folder state (no messages in folder)
@Suite("BrevMail view snapshots")
struct BrevMailViewSnapshotTests {
    // MARK: - Fixtures

    /// A fixed reference date so row date labels are deterministic across
    /// runs. The value has no semantic significance beyond stability.
    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    /// Unread message — no attachments, not flagged.
    private static let unreadHeader = MessageHeader(
        id: "snap-unread",
        threadID: "snap-thread-unread",
        folderID: "inbox",
        from: Correspondent(name: "Ada Nyström", email: "ada@example.org"),
        to: [Correspondent(email: "henrik@example.org")],
        subject: "Design feedback on the density pass",
        snippet: "Two small tweaks before we ship — notes are inline.",
        date: referenceDate,
        isRead: false
    )

    /// Read + flagged message — no attachments.
    private static let flaggedReadHeader = MessageHeader(
        id: "snap-flagged-read",
        threadID: "snap-thread-flagged",
        folderID: "inbox",
        from: Correspondent(name: "Alex Berg", email: "alex@example.org"),
        to: [Correspondent(email: "henrik@example.org")],
        subject: "Re: Sprint planning notes",
        snippet: "Looks good — flagged so we revisit after the holiday.",
        date: referenceDate,
        isRead: true,
        isFlagged: true
    )

    /// Unread message that has at least one attachment.
    private static let attachmentHeader = MessageHeader(
        id: "snap-attachment",
        threadID: "snap-thread-attachment",
        folderID: "inbox",
        from: Correspondent(name: "GitHub", email: "noreply@github.com"),
        to: [Correspondent(email: "henrik@example.org")],
        subject: "[brev] review — attached logs",
        snippet: "Build failed. Attaching the full CI log for triage.",
        date: referenceDate,
        isRead: false,
        hasAttachments: true
    )

    /// Inbox folder with six unread messages — matches MockBackend.previewFolders.
    private static let inboxFolder = Folder(
        id: "inbox",
        name: "Inbox",
        role: .inbox,
        unreadCount: 6,
        totalCount: 16
    )

    /// Archive folder with zero unread messages.
    private static let archiveFolder = Folder(
        id: "archive",
        name: "Archive",
        role: .archive,
        unreadCount: 0,
        totalCount: 312
    )

    // MARK: - Helpers

    /// Wraps `view` in a `UIHostingController`, snaps it, and asserts the
    /// image against the stored baseline. On first run the baseline is
    /// recorded automatically by `swift-snapshot-testing`.
    @MainActor
    private func snap(
        _ view: some View,
        width: CGFloat,
        height: CGFloat,
        theme: BrevTheme,
        named name: String
    ) {
        let wrapped = view
            .frame(width: width, height: height)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = UIHostingController(rootView: wrapped)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: name
        )
    }

    /// Builds a `MessageListRow` from `header` using the default display
    /// settings used throughout the existing smoke tests.
    private func messageListRow(
        header: MessageHeader,
        isSelected: Bool = false
    ) -> some View {
        MessageListRow(
            header: header,
            threadCount: 1,
            isSelected: isSelected,
            isChecked: false,
            isInSelectionMode: false,
            isPinned: false,
            isThreadExpanded: false,
            showAvatar: true,
            previewLineCount: 1,
            fontFamily: .system,
            textSize: .medium,
            density: .comfortable,
            showsAbsoluteArrivalTime: false,
            sourceContext: nil,
            isBlockedSender: false,
            hasFollowUp: false,
            onActivate: {},
            onToggleCheck: {},
            onToggleThread: {}
        )
    }

    // MARK: - Test cases

    /// Case 1 — message list row in the unread state.
    ///
    /// Unread dot should be filled with the accent colour; sender name and
    /// subject should use the primary/secondary text styles.
    @Test("MessageListRow renders unread state in default theme")
    @MainActor
    func messageListRowUnreadState() {
        let theme = BrevTheme.brevPaper
        snap(
            messageListRow(header: Self.unreadHeader),
            width: 360,
            height: 72,
            theme: theme,
            named: "message-list-row-unread"
        )
    }

    /// Case 2 — message list row that is read and flagged.
    ///
    /// Unread dot should be clear; flag icon should appear in the warning
    /// colour on the trailing edge.
    @Test("MessageListRow renders flagged + read state in default theme")
    @MainActor
    func messageListRowFlaggedReadState() {
        let theme = BrevTheme.brevPaper
        snap(
            messageListRow(header: Self.flaggedReadHeader),
            width: 360,
            height: 72,
            theme: theme,
            named: "message-list-row-flagged-read"
        )
    }

    /// Case 3 — message list row with an attachment indicator.
    ///
    /// A paperclip icon should appear on the trailing edge alongside the
    /// unread dot on the leading side.
    @Test("MessageListRow renders attachment indicator in default theme")
    @MainActor
    func messageListRowWithAttachment() {
        let theme = BrevTheme.brevPaper
        snap(
            messageListRow(header: Self.attachmentHeader),
            width: 360,
            height: 72,
            theme: theme,
            named: "message-list-row-attachment"
        )
    }

    /// Case 4 — folder sidebar rendered showing only the inbox row so the
    /// unread badge (count = 6) is the focus of the snapshot.
    @Test("FolderSidebar inbox row renders unread count badge in default theme")
    @MainActor
    func folderSidebarInboxWithUnreadBadge() {
        let theme = BrevTheme.brevPaper
        let navigation = MailNavigationState()
        navigation.selectedFolderID = Self.inboxFolder.id

        let view = FolderSidebar(
            navigation: navigation,
            folders: [Self.inboxFolder]
        )
        snap(view, width: 260, height: 52, theme: theme, named: "folder-sidebar-inbox-unread")
    }

    /// Case 5 — folder sidebar showing a folder row that has no unread
    /// messages, so no badge should appear.
    @Test("FolderSidebar archive row renders without unread badge in default theme")
    @MainActor
    func folderSidebarArchiveNoUnread() {
        let theme = BrevTheme.brevPaper
        let navigation = MailNavigationState()
        navigation.selectedFolderID = Self.archiveFolder.id

        let view = FolderSidebar(
            navigation: navigation,
            folders: [Self.archiveFolder]
        )
        snap(view, width: 260, height: 52, theme: theme, named: "folder-sidebar-archive-no-unread")
    }

    /// Case 6 — the empty folder state placeholder, shown when a folder
    /// contains no messages and no search is active.
    @Test("MessageListEmptyStateView renders empty-folder placeholder in default theme")
    @MainActor
    func messageListEmptyStateFolderEmpty() {
        let theme = BrevTheme.brevPaper
        let view = MessageListEmptyStateView(
            status: MessageListPresentation.emptyStatus(searchText: "")
        )
        snap(view, width: 320, height: 240, theme: theme, named: "message-list-empty-state")
    }
}
#endif
