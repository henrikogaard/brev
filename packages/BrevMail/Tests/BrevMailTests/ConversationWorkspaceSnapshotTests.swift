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

@Suite("Conversation workspace snapshots")
@MainActor
struct ConversationWorkspaceSnapshotTests {
    @Test("profile actions stay in the auxiliary window content")
    func profileManager() {
        let account = BrevAccount.preview
        let sections = MockBackend.previewMailboxes(for: account).map { mailbox in
            MailSourceSection(
                id: MailSourceID(accountID: account.id, mailboxID: mailbox.id),
                account: account,
                mailbox: mailbox,
                folders: []
            )
        }
        let theme = BrevTheme.brevSlate
        let view = MailProfileManagementSheet(
            availableSources: sections,
            customProfiles: [MailProfile(id: "work", name: "Work", sourceIDs: [sections[1].id])],
            onSave: { _ in },
            onClose: {}
        )
        .frame(width: 560, height: 560)
        .brevTheme(theme)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 560, height: 560)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 560)),
            named: "profile-manager",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("conversation hierarchy is readable in narrow and wide panes", arguments: [400, 760])
    func conversationLayout(width: Int) throws {
        try assertConversation(width: width, theme: .brevSlate, name: "conversation-\(width)")
    }

    @Test("wide conversations keep a bounded reading column in the default themes",
          arguments: [BrevTheme.brevMonoLight, BrevTheme.brevMonoDark])
    func wideDefaultConversation(theme: BrevTheme) throws {
        try assertConversation(width: 1200, theme: theme, name: "wide-\(theme.id)")
    }

    private func assertConversation(width: Int, theme: BrevTheme, name: String) throws {
        let source = MailSourceID(accountID: "work", mailboxID: "work")
        let headers = [
            MessageHeader(
                id: "first",
                threadID: "thread",
                folderID: "inbox",
                from: Correspondent(name: "Ingrid Halvorsen", email: "ingrid@example.com"),
                subject: "Stavanger rollout and launch checklist",
                snippet: "The rollback plan is ready for review.",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                isRead: true
            ),
            MessageHeader(
                id: "second",
                threadID: "thread",
                folderID: "inbox",
                from: Correspondent(name: "Marte Solheim", email: "marte@example.com"),
                to: [Correspondent(name: "Work mailbox", email: "work@example.com")],
                subject: "Stavanger rollout and launch checklist",
                snippet: "We can confirm the launch window.",
                date: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]
        let navigation = MailNavigationState(
            selectedSourceID: source,
            selectedFolderID: "inbox",
            selectedMessageID: "second",
            currentFolderHeaders: headers
        )
        let bodies = Dictionary(uniqueKeysWithValues: headers.map { header in
            (
                header.id,
                RenderedBody(
                    html: nil,
                    plainText: "Hi team,\n\nWe can confirm Tuesday's launch window. The rollback plan and support rota are ready for review.\n\nPlease share any final changes before Monday afternoon.\n\nThanks,\nMarte",
                    attachments: []
                )
            )
        })
        let defaults = try #require(UserDefaults(suiteName: "ConversationWorkspaceSnapshotTests-\(width)-\(theme.id)"))
        defaults.removePersistentDomain(forName: "ConversationWorkspaceSnapshotTests-\(width)-\(theme.id)")
        defer { defaults.removePersistentDomain(forName: "ConversationWorkspaceSnapshotTests-\(width)-\(theme.id)") }
        let view = ThreadConversationView(
            threadHeaders: headers,
            backend: MockBackend(),
            sourceID: source,
            navigation: navigation,
            preloadedBodies: bodies,
            showsAvatars: false,
            autoScrollsToExpandedMessage: false,
            dateTextProvider: { _ in "Sep 4, 14:20" }
        )
        .frame(width: CGFloat(width), height: 600)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .htmlBodyRenderTarget(.staticSnapshot)
        .defaultAppStorage(defaults)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: width, height: 600)),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
