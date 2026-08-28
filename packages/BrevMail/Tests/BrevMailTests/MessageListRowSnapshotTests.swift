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
import AppKit
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the top-level macOS message-list row.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Message list row snapshots")
@MainActor
struct MessageListRowSnapshotTests {
    @Test("read message row keeps sender identity prominent")
    func readMessageSender() {
        let theme = BrevTheme.brevSlate
        let header = MessageHeader(
            id: "inbox:sender-emphasis",
            threadID: "thread-sender-emphasis",
            folderID: "inbox",
            from: Correspondent(name: "Henrik Øgård", email: "henrik@example.org"),
            subject: "Thread list typography",
            snippet: "The sender remains the strongest text in a read message row.",
            date: .distantPast,
            isRead: true
        )
        let view = MessageListRow(
            header: header,
            threadCount: 1,
            isSelected: false,
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
        .frame(width: 360, height: 84)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 84)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 84)),
            named: "bold-read-sender",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// Reproduces the narrow-column case ADR-0023 flags as a truncation risk:
    /// the widest absolute arrival label, a long sender, and a thread badge all
    /// competing inside the 280-point minimum message-list width. The timestamp
    /// must stay on one line and the sender must absorb the truncation.
    @Test("narrow rows keep the arrival timestamp on a single line")
    func narrowRowKeepsTimestampOnOneLine() {
        let theme = BrevTheme.brevSlate
        let header = MessageHeader(
            id: "inbox:narrow-timestamp",
            threadID: "thread-narrow-timestamp",
            folderID: "inbox",
            from: Correspondent(name: "Marcus Rodriguez-Whitfield", email: "marcus@example.org"),
            subject: "Re: Friday standup notes and the mailbox overview review",
            snippet: "Can we pull the UI polish forward so it lands with the sync work?",
            date: Self.differentYearDate,
            isRead: false
        )
        let view = MessageListRow(
            header: header,
            threadCount: 4,
            isSelected: false,
            isChecked: false,
            isInSelectionMode: false,
            isPinned: false,
            isThreadExpanded: false,
            showAvatar: true,
            previewLineCount: 1,
            fontFamily: .system,
            textSize: .medium,
            density: .comfortable,
            showsAbsoluteArrivalTime: true,
            sourceContext: nil,
            isBlockedSender: false,
            hasFollowUp: false,
            onActivate: {},
            onToggleCheck: {},
            onToggleThread: {}
        )
        .frame(width: 280, height: 84)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.calendar, Calendar(identifier: .gregorian))
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 280, height: 84)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 280, height: 84)),
            named: "narrow-single-line-timestamp",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// Unread rows must differ from read rows by more than the 8-point dot: the
    /// subject carries weight and primary colour so the state survives a glance.
    @Test("unread rows emphasise the subject alongside the dot")
    func unreadRowEmphasisesSubject() {
        assertRow(named: "unread-subject-emphasis", isRead: false, isSelected: false)
    }

    /// Selected rows tint with the accent while the window is active, instead of
    /// the neutral fill macOS reserves for inactive windows.
    @Test("selected rows tint with the accent in an active window")
    func selectedRowTintsWithAccent() {
        assertRow(named: "selected-accent-tint", isRead: true, isSelected: true)
    }

    /// Gmail-labelled rows show user labels as chips under the subject and
    /// collapse the remainder into "+N"; system labels never render.
    @Test("labelled rows show user label chips with overflow")
    func labelledRowShowsChips() {
        let theme = BrevTheme.brevSlate
        let header = MessageHeader(
            id: "inbox:gmail-labels",
            threadID: "thread-gmail-labels",
            folderID: "inbox",
            from: Correspondent(name: "Priya Sharma", email: "priya@example.org"),
            subject: "Mailbox overview review",
            snippet: "Done — ready for your pass whenever you have a moment.",
            date: .distantPast,
            isRead: true,
            labels: ["\\Inbox", "Work", "Receipts/2026", "\\Important", "Travel"]
        )
        let view = MessageListRow(
            header: header,
            threadCount: 1,
            isSelected: false,
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
        .frame(width: 360, height: 100)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 100)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 100)),
            named: "gmail-label-chips",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("compact rows keep sender and subject without preview or label clutter")
    func compactRowKeepsPrimaryMailIdentity() {
        let theme = BrevTheme.brevSlate
        let header = MessageHeader(
            id: "inbox:compact-row",
            threadID: "thread-compact-row",
            folderID: "inbox",
            from: Correspondent(name: "Marcus Rodriguez-Whitfield", email: "marcus@example.org"),
            subject: "Friday standup notes and the mailbox overview review",
            snippet: "This preview and the provider labels should yield on a compact phone row.",
            date: Self.differentYearDate,
            isRead: false,
            isFlagged: true,
            hasAttachments: true,
            labels: ["Work", "Receipts/2026", "Travel"]
        )
        let view = MessageListRow(
            header: header,
            threadCount: 2,
            isSelected: false,
            isChecked: false,
            isInSelectionMode: false,
            isPinned: false,
            isThreadExpanded: false,
            showAvatar: true,
            previewLineCount: 2,
            isCompactWidth: true,
            fontFamily: .system,
            textSize: .medium,
            density: .comfortable,
            showsAbsoluteArrivalTime: false,
            sourceContext: "All Inboxes",
            isBlockedSender: false,
            hasFollowUp: false,
            onActivate: {},
            onToggleCheck: {},
            onToggleThread: {}
        )
        .frame(width: 320, height: 72)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 72)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 320, height: 72)),
            named: "compact-primary-hierarchy",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private func assertRow(named name: String, isRead: Bool, isSelected: Bool) {
        let theme = BrevTheme.brevSlate
        let header = MessageHeader(
            id: "inbox:\(name)",
            threadID: "thread-\(name)",
            folderID: "inbox",
            from: Correspondent(name: "Priya Sharma", email: "priya@example.org"),
            subject: "Mailbox overview review",
            snippet: "Done — ready for your pass whenever you have a moment.",
            date: .distantPast,
            isRead: isRead
        )
        let view = MessageListRow(
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
        .frame(width: 360, height: 84)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 84)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 84)),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// Mid-year 2025 in UTC so the absolute label deterministically renders its
    /// longest form (date, year, and time) in every plausible test time zone,
    /// and stays in a prior year relative to any future test run.
    private static let differentYearDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "UTC"),
        year: 2025,
        month: 6,
        day: 15,
        hour: 12,
        minute: 0
    ).date!
}
#endif
