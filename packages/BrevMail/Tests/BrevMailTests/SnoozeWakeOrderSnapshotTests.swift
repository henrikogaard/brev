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
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for collapsed conversation snooze wake ordering (#297).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Snooze wake order snapshots")
@MainActor
struct SnoozeWakeOrderSnapshotTests {
    @Test("woken collapsed conversation sorts above newer mail", arguments: ["light", "dark"])
    func wokenConversationAboveNewerMail(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let baseDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2025,
            month: 6,
            day: 15,
            hour: 12,
            minute: 0
        ).date!
        let olderSnoozed = MessageHeader(
            id: "snoozed-thread",
            threadID: "thread-contract",
            folderID: "inbox",
            from: Correspondent(name: "Maya Okafor", email: "maya@northwind.example"),
            subject: "Q4 contract terms",
            snippet: "Returned to Inbox when snooze woke.",
            date: baseDate.addingTimeInterval(-3 * 86400),
            isRead: false
        )
        let newerRegular = MessageHeader(
            id: "newer-mail",
            threadID: "thread-digest",
            folderID: "inbox",
            from: Correspondent(name: "Daniel Reyes", email: "daniel@example.org"),
            subject: "Design review notes",
            snippet: "Sharing the updated notes from yesterday.",
            date: baseDate.addingTimeInterval(-3600),
            isRead: true
        )

        let sorted = MessageListSortPolicy.sorted(
            [newerRegular, olderSnoozed],
            by: .newestFirst,
            pinnedIDs: [],
            dateOverrides: [olderSnoozed.id: baseDate]
        )
        #expect(sorted.map(\.id) == ["snoozed-thread", "newer-mail"])

        let view = VStack(spacing: 0) {
            ForEach(sorted) { header in
                MessageListRow(
                    header: header,
                    threadCount: header.id == olderSnoozed.id ? 3 : 1,
                    isSelected: header.id == olderSnoozed.id,
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
        }
        .frame(width: 380, height: 176, alignment: .top)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 380, height: 176)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 380, height: 176)),
            named: "snooze-wake-order-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
