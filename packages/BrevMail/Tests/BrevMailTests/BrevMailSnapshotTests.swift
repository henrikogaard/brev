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
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// Snapshot coverage for the composite BrevMail views. Only the
/// synchronous, data-static surfaces are covered here; views that
/// fetch from the backend (message list, reading pane) are exercised
/// at the unit-test level. Snapshots are committed under
/// `__Snapshots__/` next to this file and re-recorded by setting
/// `SNAPSHOT_TESTING_RECORD=true` (see `README.md` §Snapshot tests).
@Suite("BrevMail snapshots")
struct BrevMailSnapshotTests {
    @Test(
        "FolderSidebar renders in every built-in theme",
        arguments: BrevTheme.brevBuiltIns
    )
    @MainActor
    func folderSidebarRendersInTheme(_ theme: BrevTheme) throws {
        let navigation = MailNavigationState()
        let folders = Self.nestedFolderSidebarFixture
        navigation.selectedFolderID = folders.first { $0.role == .inbox }?.id

        let view = FolderSidebar(
            navigation: navigation,
            folders: folders
        )
        .frame(width: 260, height: 480)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("FolderSidebar nested folder fixture stays deterministic")
    func folderSidebarNestedFolderFixtureStaysDeterministic() {
        let rows = FolderSidebarPresentation.visibleRows(
            folders: Self.nestedFolderSidebarFixture,
            collapsedFolderIDs: []
        )

        #expect(rows.map { $0.folder.id } == [
            "inbox",
            "sent",
            "drafts",
            "archive",
            "archive-home",
            "archive-diving",
            "archive-receipts",
            "archive-receipts-licenses",
            "archive-newsletters",
            "mailspring",
            "mailspring-snoozed",
            "promotions",
            "social-networks",
            "spam",
            "trash"
        ])
        #expect(rows.map(\.depth) == [
            0,
            0,
            0,
            0,
            1,
            1,
            1,
            2,
            1,
            0,
            1,
            0,
            0,
            0,
            0
        ])
        #expect(rows.map(\.hasChildren) == [
            false,
            false,
            false,
            true,
            false,
            false,
            true,
            false,
            false,
            true,
            false,
            false,
            false,
            false,
            false
        ])
        #expect(rows.map { $0.folder.unreadCount } == [
            6,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1479,
            0,
            0,
            591,
            14,
            87,
            1
        ])
    }

    @Test(
        "ThemePickerView renders in every built-in theme",
        arguments: BrevTheme.brevBuiltIns
    )
    @MainActor
    func themePickerRendersInTheme(_ theme: BrevTheme) throws {
        let view = ThemePickerView(themes: BrevTheme.brevBuiltIns) { _ in }
            .frame(width: 320, height: 520)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test(
        "ThreadMessageCard collapsed renders in default theme"
    )
    @MainActor
    func threadMessageCardCollapsedRenders() throws {
        let theme = BrevTheme.brevBuiltIns[0]
        let header = (MockBackend.previewMessages["inbox"] ?? [])
            .first { $0.threadID == "thread-standup" }!

        let view = ThreadMessageCard(
            header: header,
            isExpanded: false,
            backend: MockBackend(),
            sourceID: nil
        ) {}
            .frame(width: 480, height: 80)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .htmlBodyRenderTarget(.staticSnapshot)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "collapsed-\(theme.id)"
        )
    }

    @Test("ThreadConversationView renders deterministically in default theme")
    @MainActor
    func threadConversationViewRendersDeterministically() throws {
        let theme = BrevTheme.brevPaper
        let defaults = try #require(UserDefaults(suiteName: "brev.thread-conversation-snapshot"))
        defaults.removePersistentDomain(forName: "brev.thread-conversation-snapshot")
        defaults.set(false, forKey: MailboxViewPreferenceKey.useRichRenderer)
        defaults.set(false, forKey: MailboxViewPreferenceKey.allowRemoteContent)
        defaults.set(MailboxFontFamily.system.rawValue, forKey: MailboxViewPreferenceKey.fontFamily)
        defaults.set(MailboxTextSize.medium.rawValue, forKey: MailboxViewPreferenceKey.textSize)

        let navigation = MailNavigationState()
        let headers = ThreadMessageDerivation.threadHeaders(
            from: MockBackend.previewMessages["inbox"] ?? [],
            threadID: "thread-standup"
        )
        navigation.selectedMessageID = headers.last?.id
        navigation.selectedFolderID = "inbox"

        let bodies = Dictionary(
            uniqueKeysWithValues: headers.map {
                (
                    $0.id,
                    RenderedBody(
                        html: nil,
                        plainText: "Deterministic preview body for \($0.from.displayName).",
                        attachments: []
                    )
                )
            }
        )

        let view = ThreadConversationView(
            threadHeaders: headers,
            backend: MockBackend(),
            sourceID: nil,
            navigation: navigation,
            preloadedBodies: bodies,
            showsAvatars: false,
            autoScrollsToExpandedMessage: false,
        ) { _ in "May 30, 2026 at 12:00" }
            .frame(width: 390, height: 560)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .htmlBodyRenderTarget(.staticSnapshot)
            .defaultAppStorage(defaults)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "thread-conversation-deterministic-\(theme.id)"
        )
    }

    @Test("ComposeView renders the signature toolbar picker in default theme")
    @MainActor
    func composeViewRendersSignaturePicker() throws {
        let theme = BrevTheme.brevPaper
        let backend = MockBackend()
        let signatureContext = ComposeSignatureContext(
            selectedSignatureID: "sig-work",
            options: [
                ComposeSignatureOption(id: "sig-work", title: "Work", body: "Henrik\nBrev"),
                ComposeSignatureOption(id: "sig-personal", title: "Personal", body: "Henrik")
            ]
        )
        #expect(signatureContext.selectedSignature?.title == "Work")
        #expect(signatureContext.options.map(\.title) == ["Work", "Personal"])
        let view = ComposeView(
            backend: backend,
            from: backend.account,
            signatureContext: signatureContext
        )
        .frame(width: 390, height: 844)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .htmlBodyRenderTarget(.staticSnapshot)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "signature-picker"
        )
    }

    private static var nestedFolderSidebarFixture: [Folder] {
        MockBackend.previewFolders
    }
}
#endif
