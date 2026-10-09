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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// Snapshot coverage for the phone reader's related-mail footnote, which
/// replaces the grey coverage bar on iOS. Set `RECORD_SNAPSHOTS=YES` to record.
@Suite("Related conversation footnote snapshots")
@MainActor
struct RelatedConversationFootnoteSnapshotTests {
    private static let account = BrevAccount(
        id: "account-1",
        displayName: "Personal",
        emailAddress: "me@example.org"
    )
    private static let source = MailSourceID(accountID: account.id, mailboxID: "mailbox-1")

    @Test("failed lookup shows one quiet footnote line")
    func failedFootnote() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.relatedConversationLoading]
        )
        backend.relatedConversationHandler = { _, _, _, _ in
            throw ConversationLookupError.invalidSnapshot
        }
        let controller = try makeController()
        controller.updateAnchor(header: Self.header, sourceID: Self.source, backend: backend)
        await controller.awaitSettled()
        controller.loadRelatedMail()
        await controller.awaitSettled()
        assertFootnote(controller: controller, named: "failed")
    }

    @Test("partial coverage shows the partial footnote")
    func partialFootnote() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations]
        )
        backend.cachedConversationHandler = { anchor, _ in
            try ConversationSnapshot(
                anchor: anchor.location,
                members: [anchor],
                coverage: .partial,
                excludedFolderIDs: ["Junk"],
                unavailableFolderIDs: ["Archive"]
            )
        }
        let controller = try makeController()
        controller.updateAnchor(header: Self.header, sourceID: Self.source, backend: backend)
        await controller.awaitSettled()
        assertFootnote(controller: controller, named: "partial")
    }

    @Test("the plain cached state renders nothing")
    func cachedIsSilent() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations]
        )
        backend.cachedConversationHandler = { anchor, _ in
            try ConversationSnapshot(anchor: anchor.location, members: [anchor], coverage: .cached)
        }
        let controller = try makeController()
        controller.updateAnchor(header: Self.header, sourceID: Self.source, backend: backend)
        await controller.awaitSettled()
        #expect(RelatedConversationReaderPresentation(controller: controller).status == nil)
    }

    private static let header = MessageHeader(
        id: "inbox-1",
        threadID: "thread-1",
        folderID: "INBOX",
        from: Correspondent(email: "sender@example.org"),
        to: [],
        subject: "Topic",
        snippet: "",
        date: Date(timeIntervalSince1970: 86400)
    )

    private func makeController() throws -> RelatedConversationController {
        let name = "RelatedConversationFootnoteSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return RelatedConversationController(
            consentStore: RelatedConversationConsentStore(defaults: defaults)
        )
    }

    private func assertFootnote(controller: RelatedConversationController, named name: String) {
        let theme = BrevTheme.brevPaper
        let view = RelatedConversationFootnote(horizontalPadding: 16, bottomPadding: 8)
            .environment(\.relatedConversationController, controller)
            .frame(width: 390, alignment: .leading)
            .padding(.top, 8)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 48)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
