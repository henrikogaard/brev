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
import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Phone mailbox snapshots", .serialized)
@MainActor
struct PhoneMailboxSnapshotTests {
    @Test("favourites editor distinguishes account inboxes and optional shortcuts")
    func favoritesEditor() {
        let account = BrevAccount(id: "account", displayName: "Henrik", emailAddress: "me@example.org")
        let sections = ["Personal", "Work"].map { name in
            MailSourceSection(id: MailSourceID(accountID: account.id, mailboxID: name), account: account,
                              mailbox: Mailbox(id: name, email: "me@example.org", displayName: name),
                              folders: [Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 3),
                                        Folder(id: "drafts", name: "Drafts", role: .drafts, totalCount: 2),
                                        Folder(id: "sent", name: "Sent", role: .sent)])
        }
        let candidates = MailboxFavorite.candidates(sections: sections)
        var preferences = MailboxFavorites(data: Data())
        preferences.setVisible(true, id: candidates[3].id)
        let view = MailboxFavoritesEditor(data: .constant(preferences.data), candidates: candidates)
            .brevTheme(.brevMonoLight)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
                       named: "favorites-editor",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("favourites keep long account identities readable at accessibility text sizes")
    func accessibleFavorites() throws {
        let defaults = try #require(UserDefaults(suiteName: "AccessibleFavorites-" + UUID().uuidString))
        let account = BrevAccount(id: "account", displayName: "Harbour Logistics", emailAddress: "team@example.org")
        let mailbox = Mailbox(id: "operations", email: "team@example.org", displayName: "International Operations")
        let source = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        let sections = [MailSourceSection(id: source, account: account, mailbox: mailbox,
                                          folders: [Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 123),
                                                    Folder(id: "drafts", name: "Drafts", role: .drafts, totalCount: 3)])]
        let candidates = MailboxFavorite.candidates(sections: sections)
        var preferences = MailboxFavorites(data: Data())
        preferences.setVisible(true, id: candidates[2].id)
        defaults.set(preferences.data, forKey: MailboxFavorites.storageKey)
        let view = FolderSidebar(navigation: MailNavigationState(), folders: [], sourceSections: sections)
            .defaultAppStorage(defaults)
            .brevTheme(.brevMonoLight)
            .environment(\.dynamicTypeSize, .accessibility3)
            .background(BrevTheme.brevMonoLight.bgSecondary.color)
        let host = UIHostingController(rootView: view)
        let traits = UITraitCollection(traitsFrom: [
            .init(displayScale: 2),
            .init(preferredContentSizeCategory: .accessibilityExtraLarge)
        ])
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: traits), named: "accessible-favorites",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("phone settings uses compact task categories with readable large text", arguments: [false, true])
    func settingsCategories(accessibility: Bool) throws {
        let defaults = try #require(UserDefaults(suiteName: "PhoneSettings-" + UUID().uuidString))
        let view = SettingsView(accountStore: InMemoryAccountStore(), activeTheme: .constant(.brevMonoLight),
                                settingsStore: SettingsPersistenceStore(defaults: defaults))
            .brevTheme(.brevMonoLight)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
        let host = UIHostingController(rootView: view)
        let traits = UITraitCollection(traitsFrom: [.init(displayScale: 2),
                                                    .init(preferredContentSizeCategory: accessibility ? .accessibilityExtraLarge :
                                                        .large)])
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: traits),
                       named: accessibility ? "accessibility" : "standard",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("expanded inbox keeps parent and reply typography coherent", arguments: [false, true])
    func expandedInbox(accessibility: Bool) {
        let header = MessageHeader(id: "parent", threadID: "thread", folderID: "inbox",
                                   from: Correspondent(name: "Marte Solheim", email: "marte@example.org"),
                                   subject: "Stavanger rollout — terminal go-live window",
                                   snippet: "We can take the terminal offline Tuesday morning.", date: .distantPast,
                                   isRead: false)
        let reply = MessageHeader(id: "reply", threadID: "thread", folderID: "inbox",
                                  from: Correspondent(name: "Ingrid Halvorsen", email: "ingrid@example.org"),
                                  subject: header.subject, snippet: "Tuesday works. I'll have the rollback plan signed off.",
                                  date: .distantPast, isRead: false)
        let view = ScrollView {
            VStack(spacing: 0) {
                MessageListRow(header: header, threadCount: 2, isSelected: true, isChecked: false,
                               isInSelectionMode: false, isPinned: false, isThreadExpanded: true, showAvatar: true,
                               previewLineCount: 1, isCompactWidth: true, fontFamily: .system, textSize: .medium,
                               density: .comfortable, showsAbsoluteArrivalTime: false, sourceContext: nil,
                               isBlockedSender: false, hasFollowUp: false, onActivate: {}, onToggleCheck: {}, onToggleThread: {})
                ThreadInlineChildRow(header: reply, isSelected: false, onSelect: {})
            }
        }
        .brevTheme(.brevMonoLight)
        .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
        let host = UIHostingController(rootView: view)
        let traits = UITraitCollection(traitsFrom: [.init(displayScale: 2),
                                                    .init(preferredContentSizeCategory: accessibility ? .accessibilityExtraLarge :
                                                        .large)])
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: traits),
                       named: accessibility ? "expanded-accessibility" : "expanded-standard",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("search scope and filters fit a compact phone")
    func compactSearchOptions() {
        let view = MailSearchOptionsBar(execution: .constant(.cacheThenServer),
                                        availableExecutions: [.cacheOnly, .cacheThenServer, .serverOnly],
                                        folderScope: .constant(false), fieldScope: .constant(.all))
            .brevTheme(.brevMonoLight)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 100), traits: .init(displayScale: 2)),
                       named: "compact-search-options",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("invalid recipient shows a visible correction")
    func invalidRecipient() {
        let view = RecipientChipField(label: "To", recipients: .constant(["not-an-email"]), inputText: .constant(""))
            .padding(12).brevTheme(.brevMonoLight)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 170), traits: .init(displayScale: 2)),
                       named: "invalid-recipient",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

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
                                            traits: .init(displayScale: 2)), named: "narrow-compose",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
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
        let traits = UITraitCollection(traitsFrom: [
            .init(displayScale: 2),
            .init(preferredContentSizeCategory: accessibility ? .accessibilityExtraExtraExtraLarge : .large)
        ])
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: traits),
                       named: accessibility ? "accessibility" : "standard",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
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
        let traits = UITraitCollection(traitsFrom: [
            .init(displayScale: 2),
            .init(preferredContentSizeCategory: accessibility ? .accessibilityExtraExtraExtraLarge : .large)
        ])
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 720),
                                            traits: traits),
                       named: accessibility ? "accessibility" : "standard",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
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
        let host = UIHostingController(rootView: NavigationStack {
            FolderSidebar(navigation: navigation, folders: [], sourceSections: [
                MailSourceSection(id: source, account: account, mailbox: mailbox,
                                  folders: MockBackend.previewFolders)
            ])
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(theme.bgSecondary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        .defaultAppStorage(defaults))
        assertSnapshot(of: host,
                       as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
                       named: dark ? "dark" : "light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("phone sidebar distinguishes account sections from nested folders", arguments: [false, true])
    func twoAccountMailboxes(dark: Bool) throws {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let defaults = try #require(UserDefaults(suiteName: "TwoAccountSidebar-" + UUID().uuidString))
        let navigation = MailNavigationState()
        let account = BrevAccount(id: "account", displayName: "Henrik Øgård", emailAddress: "henrik@example.org")
        let personal = Mailbox(id: "personal", email: "personal@example.org", displayName: "Personal", isPrimary: true)
        let work = Mailbox(id: "work", email: "work@example.org", displayName: "Harbour Logistics and Operations")
        let personalSource = MailSourceID(accountID: account.id, mailboxID: personal.id)
        let workSource = MailSourceID(accountID: account.id, mailboxID: work.id)
        try defaults.set(JSONEncoder().encode(Set([personalSource, workSource])), forKey: "mailbox.disclosureState")
        navigation.selectFolder("inbox", in: workSource)
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 11),
            Folder(id: "drafts", name: "Drafts", role: .drafts),
            Folder(id: "archive", name: "Archive", role: .archive),
            Folder(id: "receipts", name: "Receipts", role: .custom, parentID: "archive"),
            Folder(id: "software", name: "Software", role: .custom, parentID: "receipts")
        ]
        let view = NavigationStack {
            FolderSidebar(navigation: navigation, folders: [], sourceSections: [
                MailSourceSection(id: personalSource, account: account, mailbox: personal, folders: folders),
                MailSourceSection(id: workSource, account: account, mailbox: work, folders: Array(folders.prefix(2)))
            ])
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(theme.bgSecondary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        .defaultAppStorage(defaults)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host,
                       as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
                       named: dark ? "dark" : "light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("mailboxes list with apps at the largest accessibility size")
    func mailboxesAccessibility5() throws {
        let theme = BrevTheme.brevMonoLight
        let defaults = try #require(UserDefaults(suiteName: "MailboxesAX5-" + UUID().uuidString))
        let navigation = MailNavigationState()
        let account = BrevAccount(id: "account", displayName: "Henrik Øgård", emailAddress: "henrik@example.org")
        let personal = Mailbox(
            id: "personal",
            email: "personal@example.org",
            displayName: "Henrik Øgård (private)",
            isPrimary: true
        )
        let personalSource = MailSourceID(accountID: account.id, mailboxID: personal.id)
        try defaults.set(JSONEncoder().encode(Set([personalSource])), forKey: "mailbox.disclosureState")
        navigation.selectUnifiedInbox()
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 11),
            Folder(id: "drafts", name: "Drafts", role: .drafts),
            Folder(id: "sent", name: "Sent", role: .sent)
        ]
        let view = NavigationStack {
            FolderSidebar(
                navigation: navigation, folders: [],
                sourceSections: [MailSourceSection(id: personalSource, account: account, mailbox: personal, folders: folders)],
                onOpenCalendar: {}, onOpenContacts: {}, onOpenTasks: {}
            )
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(theme.bgSecondary.color)
        .brevTheme(theme)
        .environment(\.dynamicTypeSize, .accessibility5)
        .defaultAppStorage(defaults)
        let host = UIHostingController(rootView: view)
        let traits = UITraitCollection(traitsFrom: [
            .init(displayScale: 2),
            .init(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ])
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: traits), named: "ax5",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("iPad sidebar wraps long account names instead of truncating them")
    func ipadSidebarLongAccountName() throws {
        let theme = BrevTheme.brevMonoLight
        let defaults = try #require(UserDefaults(suiteName: "IPadSidebar-" + UUID().uuidString))
        let navigation = MailNavigationState()
        let account = BrevAccount(id: "account", displayName: "Henrik Øgård", emailAddress: "henrik@example.org")
        let personal = Mailbox(
            id: "personal",
            email: "personal@example.org",
            displayName: "Henrik Øgård (private)",
            isPrimary: true
        )
        let work = Mailbox(id: "work", email: "work@example.org", displayName: "Henrik Øgård (work, Harbour Logistics)")
        let personalSource = MailSourceID(accountID: account.id, mailboxID: personal.id)
        let workSource = MailSourceID(accountID: account.id, mailboxID: work.id)
        try defaults.set(JSONEncoder().encode(Set([personalSource])), forKey: "mailbox.disclosureState")
        navigation.selectFolder("inbox", in: personalSource)
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 11),
            Folder(id: "drafts", name: "Drafts", role: .drafts)
        ]
        let view = NavigationStack {
            FolderSidebar(navigation: navigation, folders: [], sourceSections: [
                MailSourceSection(id: personalSource, account: account, mailbox: personal, folders: folders),
                MailSourceSection(id: workSource, account: account, mailbox: work, folders: folders)
            ])
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(theme.bgSecondary.color)
        .brevTheme(theme)
        .defaultAppStorage(defaults)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 640), traits: .init(displayScale: 2)),
                       named: "ipad-sidebar",
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
