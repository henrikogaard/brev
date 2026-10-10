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

/// Snapshot coverage for the iPhone message list rows: unread dot, selection circle,
/// compact unified row, accessibility size and the non-interactive date header.
/// Set `RECORD_SNAPSHOTS=YES` to record.
@Suite("Phone message list snapshots")
@MainActor
struct PhoneMessageListSnapshotTests {
    private static func header(isRead: Bool) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "thread-snapshot",
            folderID: "inbox",
            from: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
            to: [Correspondent(name: "Henrik", email: "henrik@ogard.example")],
            subject: "Hytte weekend in Hemsedal",
            snippet: "Booked the cabin for three nights, bring the sleeping bags.",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: isRead
        )
    }

    private func row(
        isRead: Bool,
        isChecked: Bool = false,
        isInSelectionMode: Bool = false,
        sourceContext: String? = nil
    ) -> some View {
        MessageListRow(
            header: Self.header(isRead: isRead),
            threadCount: 1,
            isSelected: false,
            isChecked: isChecked,
            isInSelectionMode: isInSelectionMode,
            isPinned: false,
            isThreadExpanded: false,
            showAvatar: true,
            previewLineCount: 1,
            isCompactWidth: true,
            fontFamily: .system,
            textSize: .medium,
            density: .comfortable,
            showsAbsoluteArrivalTime: true,
            sourceContext: sourceContext,
            isBlockedSender: false,
            hasFollowUp: false,
            onActivate: {},
            onToggleCheck: {},
            onToggleThread: {}
        )
    }

    @Test("unread rows show the accent dot and a semibold sender, read rows do not", arguments: [false, true])
    func unreadAndReadRows(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : BrevTheme.brevMonoLight
        let view = VStack(spacing: 0) {
            row(isRead: false)
            row(isRead: true)
        }
        .frame(width: 390, height: 220)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        assertSnapshot(
            of: host(view, width: 390, height: 220, dark: dark),
            as: .image(size: CGSize(width: 390, height: 220), traits: .init(displayScale: 2)),
            named: dark ? "unread-read-dark" : "unread-read-light",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("compact All Inboxes row drops the repeated account line")
    func compactUnifiedRow() {
        let theme = BrevTheme.brevMonoLight
        let view = row(isRead: false, sourceContext: "Work · henrik@work.example")
            .frame(width: 390, height: 110)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        assertSnapshot(
            of: host(view, width: 390, height: 110, dark: false),
            as: .image(size: CGSize(width: 390, height: 110), traits: .init(displayScale: 2)),
            named: "unified-compact-row",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("selection mode rows show a scalable circle, ticked and unticked")
    func selectionRows() {
        let theme = BrevTheme.brevMonoLight
        let view = VStack(spacing: 0) {
            row(isRead: false, isChecked: true, isInSelectionMode: true)
            row(isRead: true, isChecked: false, isInSelectionMode: true)
        }
        .frame(width: 390, height: 230)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        assertSnapshot(
            of: host(view, width: 390, height: 230, dark: false),
            as: .image(size: CGSize(width: 390, height: 230), traits: .init(displayScale: 2)),
            named: "selection-rows",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("row at accessibility text size uses the stacked layout")
    func accessibilityRow() {
        let theme = BrevTheme.brevMonoLight
        let view = row(isRead: false)
            .frame(width: 390, height: 520)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .dynamicTypeSize(.accessibility5)
        assertSnapshot(
            of: host(view, width: 390, height: 520, dark: false),
            as: .image(size: CGSize(width: 390, height: 520), traits: .init(displayScale: 2)),
            named: "row-accessibility5",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("phone date header is a plain heading without a disclosure chevron")
    func dateHeader() {
        let theme = BrevTheme.brevMonoLight
        let view = VStack(spacing: 0) {
            MessageListDateSectionHeader(
                title: "Yesterday",
                count: 2,
                isCollapsed: false,
                isCollapsible: false,
                onToggle: {}
            )
            MessageListDateSectionHeader(
                title: "Yesterday",
                count: 2,
                isCollapsed: false,
                isCollapsible: true,
                onToggle: {}
            )
        }
        .frame(width: 390, height: 70)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        assertSnapshot(
            of: host(view, width: 390, height: 70, dark: false),
            as: .image(size: CGSize(width: 390, height: 70), traits: .init(displayScale: 2)),
            named: "date-header",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("empty state uses the system layout with readable, undimmed colours")
    func emptyState() {
        let theme = BrevTheme.brevMonoLight
        let view = MessageListEmptyStateView(
            status: MessageListStatus(
                title: "No messages",
                icon: "tray",
                subtitle: "This mailbox is empty.",
                actionTitle: "Clear filters"
            ),
            onAction: {}
        )
        .frame(width: 390, height: 320)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        assertSnapshot(
            of: host(view, width: 390, height: 320, dark: false),
            as: .image(size: CGSize(width: 390, height: 320), traits: .init(displayScale: 2)),
            named: "empty-state",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private func host(_ view: some View, width: CGFloat, height: CGFloat, dark: Bool) -> UIViewController {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return host
    }
}
#endif
