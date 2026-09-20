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
    @Test("detached reader controls have touch-sized layout")
    func detachedReader() {
        let header = MessageHeader(id: "message", threadID: "thread", folderID: "inbox",
                                   from: Correspondent(name: "Harbour Logistics", email: "team@example.org"),
                                   subject: "Terminal update", snippet: "Preview", date: .distantPast)
        let view = MessageDetailView(backend: MockBackend(), header: header,
                                     allFolders: MockBackend.previewFolders, closeWindow: {})
            .environment(\.horizontalSizeClass, .regular)
            .brevTheme(.brevMonoLight)
            .htmlBodyRenderTarget(.staticSnapshot)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 660, height: 560),
                                            traits: .init(displayScale: 2)), named: "detached-reader",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("summary retry has a touch-sized layout")
    func summaryRetry() {
        let view = ThreadAISummaryPanel(
            state: .failure(message: "Summary unavailable. Try again.", providerLabel: "Configured provider"),
            onRetry: {}
        )
        .brevTheme(.brevMonoLight)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 350, height: 220),
                                            traits: .init(displayScale: 2)), named: "summary-retry",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("compose actions fit a narrow regular-width scene")
    func narrowCompose() {
        let backend = MockBackend()
        let view = ComposeView(backend: backend, from: backend.account,
                               signatureContext: ComposeSignatureContext(
                                   selectedSignatureID: "work",
                                   options: [.init(id: "work", title: "Work signature", body: "Best regards")]
                               ))
                               .environment(\.horizontalSizeClass, .regular)
                               .brevTheme(.brevMonoLight)
                               .htmlBodyRenderTarget(.staticSnapshot)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 660, height: 560),
                                            traits: .init(displayScale: 2)), named: "narrow-compose")
    }

    @Test("conversation metadata stays secondary at phone text sizes", arguments: [false, true])
    func conversation(accessibility: Bool) throws {
        let header = MessageHeader(
            id: "message", threadID: "thread", folderID: "inbox",
            from: Correspondent(name: "Marte Solheim", email: "marte@example.org"),
            subject: "Stavanger rollout — terminal go-live window",
            snippet: "The rollback plan is ready.", date: .distantPast
        )
        let defaults = try #require(UserDefaults(suiteName: "PhoneReader-" + UUID().uuidString))
        let view = ThreadConversationView(
            threadHeaders: [header], backend: MockBackend(),
            mailboxLabel: "henrik@ogard.example",
            navigation: MailNavigationState(selectedMessageID: header.id),
            preloadedBodies: [header.id: RenderedBody(html: nil,
                                                      plainText: "Hi team,\n\nThe rollback plan is ready. We can confirm Tuesday's launch window.\n\nThanks,\nMarte",
                                                      attachments: [])],
            showsAvatars: false, autoScrollsToExpandedMessage: false,
            dateTextProvider: { _ in "10:38" }
        )
        .brevTheme(.brevMonoLight)
        .htmlBodyRenderTarget(.staticSnapshot)
        .defaultAppStorage(defaults)
        .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
                       named: accessibility ? "accessibility" : "standard")
    }

    @Test("phone compose stays inside the viewport", arguments: [false, true])
    func phoneCompose(accessibility: Bool) {
        let backend = MockBackend()
        let view = ComposeView(backend: backend, from: backend.account)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
            .brevTheme(.brevMonoLight)
            .htmlBodyRenderTarget(.staticSnapshot)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 720),
                                            traits: .init(displayScale: 2)),
                       named: accessibility ? "accessibility" : "standard")
    }

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
