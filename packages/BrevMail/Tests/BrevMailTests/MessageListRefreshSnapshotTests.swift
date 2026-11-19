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

/// The refreshed message list (#306 slice 2): header with an unread count,
/// pill tabs, and rows with the thread count after the sender and the clip
/// beside the time. Set `RECORD_SNAPSHOTS=YES` to record the baselines.
@Suite("Message list refresh snapshots")
@MainActor
struct MessageListRefreshSnapshotTests {
    @Test("header subtitle joins the account and the unread count")
    func subtitle() {
        #expect(MailListTitle.subtitle(context: "Personal", unreadCount: 67) == "Personal · 67 unread")
        #expect(MailListTitle.subtitle(context: nil, unreadCount: 3) == "3 unread")
        #expect(MailListTitle.subtitle(context: "Personal", unreadCount: 0) == "Personal")
        #expect(MailListTitle.subtitle(context: "", unreadCount: nil) == nil)
    }

    @Test("list header, tabs and rows across light and dark themes", arguments: [
        "brevMonoLight", "brevMonoDark", "solarizedLight", "solarizedDark", "gruvboxLight", "gruvboxDark",
    ])
    func list(_ themeName: String) throws {
        let theme = try #require(Self.theme(named: themeName))
        let rows = [
            Self.row(Self.header("1", "Maya Okafor", "Q4 roadmap: final review", isRead: false, attachments: true),
                     threadCount: 3, isSelected: false),
            Self.row(Self.header("2", "Daniel Reyes", "Onboarding copy", isRead: false, attachments: false),
                     threadCount: 1, isSelected: true),
            Self.row(Self.header("3", "Priya Natarajan", "Dinner on Saturday?", isRead: true, attachments: true),
                     threadCount: 2, isSelected: false),
        ]
        let view = VStack(spacing: 0) {
            MailListTitle(title: "Inbox", context: "Personal", unreadCount: 67)
            InboxCategoryBar(activeCategory: .constant(.primary))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in row }
            Spacer(minLength: 0)
        }
        .frame(width: 420, height: 340)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: theme.mode.colorScheme == .dark ? .darkAqua : .aqua)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 420, height: 340)), named: themeName,
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    private static func theme(named name: String) -> BrevTheme? {
        switch name {
        case "brevMonoLight": .brevMonoLight
        case "brevMonoDark": .brevMonoDark
        case "solarizedLight": .solarizedLight
        case "solarizedDark": .solarizedDark
        case "gruvboxLight": .gruvboxLight
        case "gruvboxDark": .gruvboxDark
        default: nil
        }
    }

    private static func header(_ id: String, _ name: String, _ subject: String, isRead: Bool,
                               attachments: Bool) -> MessageHeader {
        MessageHeader(
            id: id, threadID: "t" + id, folderID: "inbox",
            from: Correspondent(name: name, email: name.lowercased().replacingOccurrences(of: " ", with: ".")
                + "@example.com"),
            subject: subject, snippet: "A short preview of the message that runs on for a while.",
            date: .distantPast, isRead: isRead, hasAttachments: attachments
        )
    }

    private static func row(_ header: MessageHeader, threadCount: Int, isSelected: Bool) -> MessageListRow {
        MessageListRow(
            header: header, threadCount: threadCount, isSelected: isSelected, isChecked: false,
            isInSelectionMode: false, isPinned: false, isThreadExpanded: false, showAvatar: true,
            previewLineCount: 1, fontFamily: .system, textSize: .medium, density: .comfortable,
            showsAbsoluteArrivalTime: false, sourceContext: nil, isBlockedSender: false, hasFollowUp: false,
            onActivate: {}, onToggleCheck: {}, onToggleThread: {}
        )
    }
}
#endif
