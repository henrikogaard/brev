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

/// Snapshot coverage for global sidebar controls above the account tree.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Folder sidebar snapshots")
@MainActor
struct FolderSidebarSnapshotTests {
    @Test("profiles show independently expanded mailbox groups", arguments: ["light", "dark"])
    func compactProfileScopes(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let account = BrevAccount(id: "account", displayName: "Demo", emailAddress: "me@example.org")
        let privateBox = Mailbox(id: "private", email: "me@example.org", displayName: "Private")
        let workBox = Mailbox(id: "work", email: "me@work.example", displayName: "Work")
        let privateSource = MailSourceID(accountID: account.id, mailboxID: privateBox.id)
        let workSource = MailSourceID(accountID: account.id, mailboxID: workBox.id)
        let folders = [Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 5),
                       Folder(id: "drafts", name: "Drafts", role: .drafts),
                       Folder(id: "sent", name: "Sent", role: .sent),
                       Folder(id: "archive", name: "Archive", role: .archive)]
        let sources = [MailSourceSection(id: privateSource, account: account, mailbox: privateBox, folders: folders),
                       MailSourceSection(id: workSource, account: account, mailbox: workBox, folders: folders)]
        let focused = MailProfile(id: "focused", name: "Focused", sourceIDs: [workSource])
        let profiles = [MailProfile.allMailboxes(sourceIDs: [privateSource, workSource]), focused]
        for scope in ["aggregate", "mailbox", "profile", "collapsed"] {
            let suiteName = "MailboxGroupSnapshots-" + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let expanded: Set<MailSourceID> = scope == "collapsed" ? [] : [privateSource, workSource]
            try defaults.set(JSONEncoder().encode(expanded), forKey: "mailbox.disclosureState")
            let nav = MailNavigationState()
            if scope == "mailbox" { nav.selectFolder("inbox", in: workSource) }
            else { nav.selectUnifiedInbox() }
            let view = FolderSidebar(navigation: nav, folders: [],
                                     sourceSections: scope == "profile" ? [sources[1]] : sources,
                                     profiles: profiles,
                                     activeProfileID: scope == "profile" ? focused.id : MailProfile.allMailboxesID,
                                     onSelectProfile: { _ in }, onManageProfiles: {})
                .frame(width: 240, height: 520)
                .background(theme.bgSecondary.color)
                .brevTheme(theme)
                .environment(\.colorScheme, theme.mode.colorScheme)
                .defaultAppStorage(defaults)
            let host = NSHostingController(rootView: view)
            host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 240, height: 520)),
                           named: scope + "-" + mode,
                           record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
        }
    }

    @Test("Smart Views expose Today plus create and manage controls")
    func smartViewsExposeTodayAndManagement() throws {
        let suiteName = "FolderSidebarSnapshots-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let account = BrevAccount.preview
        let mailbox = try #require(MockBackend.previewMailboxes(for: account).first)
        let sourceID = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        let navigation = MailNavigationState()
        navigation.selectTodaySmartView()

        let theme = BrevTheme.brevPaper
        let view = FolderSidebar(
            navigation: navigation,
            folders: [],
            sourceSections: [
                MailSourceSection(
                    id: sourceID,
                    account: account,
                    mailbox: mailbox,
                    folders: MockBackend.previewFolders
                ),
            ]
        )
        .frame(width: 260, height: 420)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .defaultAppStorage(defaults)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 260, height: 420)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 260, height: 420)),
            named: "smart-views-today-management",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("All Inboxes aligns with the account-level sidebar content")
    func allInboxesGlobalAlignment() throws {
        let suiteName = "FolderSidebarSnapshots-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let personal = BrevAccount.preview
        let personalMailbox = try #require(MockBackend.previewMailboxes(for: personal).first)
        let personalSourceID = MailSourceID(
            accountID: personal.id,
            mailboxID: personalMailbox.id
        )
        let work = BrevAccount(
            id: "work-account",
            displayName: "Henrik Øgård (work)",
            emailAddress: "henrik.ogard@acme.example",
            backendIdentifier: "demo",
            backendDisplayName: "Demo"
        )
        let workMailbox = Mailbox(
            id: work.id,
            email: work.emailAddress,
            displayName: work.displayName,
            isPrimary: true
        )
        let workSourceID = MailSourceID(accountID: work.id, mailboxID: workMailbox.id)
        let navigation = MailNavigationState()
        navigation.selectUnifiedInbox()

        let theme = BrevTheme.brevPaper
        let view = FolderSidebar(
            navigation: navigation,
            folders: [],
            sourceSections: [
                MailSourceSection(
                    id: personalSourceID,
                    account: personal,
                    mailbox: personalMailbox,
                    folders: MockBackend.previewFolders
                ),
                MailSourceSection(
                    id: workSourceID,
                    account: work,
                    mailbox: workMailbox,
                    folders: MockBackend.previewFolders
                ),
            ]
        )
        .frame(width: 240, height: 320)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .defaultAppStorage(defaults)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 240, height: 320)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 240, height: 320)),
            named: "all-inboxes-global-alignment",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Gmail-native source shows provider mailbox names and All Mail")
    func gmailNativeSourceUsesProviderSidebarNames() throws {
        let suiteName = "FolderSidebarSnapshots-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let account = BrevAccount(
            id: "gmail-api:subject",
            displayName: "Henrik Ogard",
            emailAddress: "henrik@example.com",
            backendIdentifier: "gmail-api",
            backendDisplayName: "Gmail"
        )
        let mailbox = Mailbox(
            id: "primary",
            email: account.emailAddress,
            displayName: account.displayName,
            isPrimary: true
        )
        let sourceID = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        let navigation = MailNavigationState()
        navigation.selectedSourceID = sourceID
        navigation.selectedFolderID = "INBOX"

        let folders = [
            Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 3),
            Folder(id: "STARRED", name: "Starred", role: .starred),
            Folder(id: "IMPORTANT", name: "Important", role: .custom),
            Folder(id: "ALL_MAIL", name: "All Mail", role: .allMail),
            Folder(id: "Projects", name: "Projects", role: .custom),
            Folder(id: "Projects/2026", name: "Projects/2026", role: .custom, parentID: "Projects"),
            Folder(id: "SPAM", name: "Spam", role: .spam),
            Folder(id: "TRASH", name: "Trash", role: .trash),
        ]
        let theme = BrevTheme.brevPaper
        let view = FolderSidebar(
            navigation: navigation,
            folders: [],
            sourceSections: [
                MailSourceSection(
                    id: sourceID,
                    account: account,
                    mailbox: mailbox,
                    folders: folders
                ),
            ],
            capabilitiesForSource: { _ in [.providerAPI, .labels, .serverSideThreading] }
        )
        .frame(width: 260, height: 360)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .defaultAppStorage(defaults)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 260, height: 360)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 260, height: 360)),
            named: "gmail-native-sidebar",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
