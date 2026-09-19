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

#if os(iOS)
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Phone mailbox snapshots", .serialized)
@MainActor
struct PhoneMailboxSnapshotTests {
    @Test("phone folder hierarchy", arguments: [false, true])
    func mailboxes(dark: Bool) throws {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let defaults = try #require(UserDefaults(suiteName: "PhoneMailboxSnapshots-" + UUID().uuidString))
        let navigation = MailNavigationState()
        let account = BrevAccount(id: "account", displayName: "Personal", emailAddress: "me@example.org")
        let mailbox = Mailbox(id: "personal", email: "me@example.org", displayName: "Personal", isPrimary: true)
        let source = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        navigation.selectFolder("INBOX", in: source)
        let host = UIHostingController(rootView:
            FolderSidebar(navigation: navigation, folders: [], sourceSections: [
                MailSourceSection(id: source, account: account, mailbox: mailbox,
                                  folders: MockBackend.previewFolders)
            ])
            .background(theme.bgSecondary.color)
            .brevTheme(theme)
            .environment(\.colorScheme, dark ? .dark : .light)
            .defaultAppStorage(defaults))
        assertSnapshot(of: host,
                       as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
                       named: dark ? "dark" : "light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("phone search and message typography", arguments: [false, true])
    func inbox(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let header = MessageHeader(
            id: "message", threadID: "thread", folderID: "inbox",
            from: Correspondent(name: "Harbour Logistics", email: "team@example.org"),
            subject: "Stavanger rollout — terminal go-live window",
            snippet: "We can take the terminal offline Tuesday morning. Does that work for you?",
            date: .distantPast, isRead: false
        )
        let view = VStack(spacing: 0) {
            MessageListSearchField(text: .constant(""), prompt: "Search messages")
                .padding(12)
            MessageListRow(
                header: header, threadCount: 1, isSelected: false, isChecked: false,
                isInSelectionMode: false, isPinned: false, isThreadExpanded: false,
                showAvatar: true, previewLineCount: 1, isCompactWidth: true,
                fontFamily: .system, textSize: .medium, density: .comfortable,
                showsAbsoluteArrivalTime: true, sourceContext: nil,
                isBlockedSender: false, hasFollowUp: false,
                onActivate: {}, onToggleCheck: {}, onToggleThread: {}
            )
            Spacer()
        }
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host,
                       as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
                       named: dark ? "dark" : "light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}
#endif
