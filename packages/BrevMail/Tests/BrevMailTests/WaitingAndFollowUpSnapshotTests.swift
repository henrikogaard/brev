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

/// macOS snapshot coverage for the Waiting smart view in the sidebar and the
/// no-reply follow-up indicator / compose reminder toggle (#297).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Waiting and follow-up snapshots")
@MainActor
struct WaitingAndFollowUpSnapshotTests {
    @Test("sidebar Waiting smart view and follow-up indicator render cleanly", arguments: ["light", "dark"])
    func waitingSidebarAndFollowUp(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suiteName = "WaitingFollowUpSnapshot-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = BrevAccount(id: "account", displayName: "Demo", emailAddress: "alex@example.org")
        let box = Mailbox(id: "primary", email: "alex@example.org", displayName: "Personal")
        let source = MailSourceID(accountID: account.id, mailboxID: box.id)
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 3),
            Folder(id: "sent", name: "Sent", role: .sent),
            Folder(id: "archive", name: "Archive", role: .archive),
        ]
        let section = MailSourceSection(id: source, account: account, mailbox: box, folders: folders)
        let navigation = MailNavigationState()
        navigation.selectWaitingSmartView()

        let waitingDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2025,
            month: 6,
            day: 15,
            hour: 12,
            minute: 0
        ).date!
        let waitingHeader = MessageHeader(
            id: "sent-followup",
            threadID: "thread-followup",
            folderID: "sent",
            from: Correspondent(name: "Alex Chen", email: "alex@example.org"),
            to: [Correspondent(name: "Maya Okafor", email: "maya@northwind.example")],
            subject: "Signed agreement",
            snippet: "Checking in on the countersigned copy.",
            date: waitingDate,
            isRead: true
        )

        let view = HStack(alignment: .top, spacing: 0) {
            FolderSidebar(navigation: navigation, folders: folders, sourceSections: [section])
                .frame(width: 240, height: 420)
                .background(theme.bgSecondary.color)
            Divider()
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                MessageListRow(
                    header: waitingHeader,
                    threadCount: 1,
                    isSelected: true,
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
                    hasFollowUp: true,
                    onActivate: {},
                    onToggleCheck: {},
                    onToggleThread: {}
                )
                Divider()
                Toggle(
                    String(localized: "Remind me if no reply in 3 days", bundle: .module),
                    isOn: .constant(true)
                )
                .padding(.horizontal, BrevSpacing.md)
                Spacer(minLength: 0)
            }
            .frame(width: 360, height: 420)
            .background(theme.bgPrimary.color)
        }
        .frame(width: 601, height: 420)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .defaultAppStorage(defaults)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 601, height: 420)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 601, height: 420)),
            named: "waiting-and-followup-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
