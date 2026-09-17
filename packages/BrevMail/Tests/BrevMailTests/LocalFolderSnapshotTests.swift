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

/// Snapshot coverage for the ADR-0077 local-folder surfaces: the "On My Mac"
/// sidebar section and the Copy/Move-to-local destination sheet.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baselines.
@Suite("Local folder snapshots")
@MainActor
struct LocalFolderSnapshotTests {
    @Test("local account section renders its folders", arguments: ["light", "dark"])
    func localAccountSection(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let localAccount = BrevAccount(
            id: LocalMailBackend.accountID,
            displayName: "On My Mac",
            emailAddress: "",
            backendIdentifier: LocalMailBackend.backendIdentifier,
            backendDisplayName: "On My Mac"
        )
        let mailbox = Mailbox(id: "local", email: "", displayName: "On My Mac")
        let sourceID = MailSourceID(accountID: localAccount.id, mailboxID: mailbox.id)
        let folders = [
            Folder(id: "saved", name: "Saved receipts", role: .custom, unreadCount: 2),
            Folder(id: "tax", name: "Tax 2026", role: .custom)
        ]
        let section = MailSourceSection(
            id: sourceID, account: localAccount, mailbox: mailbox, folders: folders
        )
        let nav = MailNavigationState()
        let view = FolderSidebar(
            navigation: nav,
            folders: [],
            sourceSections: [section],
            profiles: [MailProfile.allMailboxes(sourceIDs: [sourceID])],
            activeProfileID: MailProfile.allMailboxesID,
            mailboxes: [mailbox],
            onNewLocalFolder: {}
        )
        .frame(width: 240, height: 320)
        .background(theme.bgSecondary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 240, height: 320)),
            named: "local-section-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("destination sheet lists local folders and a New Folder field", arguments: ["light", "dark"])
    func destinationSheet(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let folders = [
            Folder(id: "saved", name: "Saved receipts", role: .custom),
            Folder(id: "tax", name: "Tax 2026", role: .custom)
        ]
        let view = MoveToSheet(
            allFolders: folders,
            messageIDs: ["m1"],
            title: "Copy to Local Folder",
            onMove: { _, _ in },
            onCreateFolder: { _ in folders[0] }
        )
        .frame(width: 360, height: 420)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 420)),
            named: "destination-sheet-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
