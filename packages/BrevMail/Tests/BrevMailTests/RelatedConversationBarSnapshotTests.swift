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

/// Snapshot coverage for the reader's related-conversation feedback bar.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Related conversation bar snapshots")
@MainActor
struct RelatedConversationBarSnapshotTests {
    /// Before any lookup: the bar explains the feature and offers the
    /// explicit opt-in action.
    @Test("prompt state offers the Load related mail action")
    func promptOffersLoadAction() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations, .relatedConversationLoading]
        )
        let controller = try makeController()
        controller.updateAnchor(
            header: Self.header(id: "inbox-1"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()
        assertBar(controller: controller, named: "prompt-load-action")
    }

    /// A cached-only snapshot reports its coverage without a remote
    /// affordance when the backend cannot load remotely.
    @Test("cached snapshot reports cached coverage")
    func cachedCoverage() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations]
        )
        backend.cachedConversationHandler = { anchor, _ in
            try Self.snapshot(anchor: anchor, members: [anchor])
        }
        let controller = try makeController()
        controller.updateAnchor(
            header: Self.header(id: "inbox-1"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()
        assertBar(controller: controller, named: "cached-coverage")
    }

    /// Partial coverage surfaces Retry and the Spam/Trash inclusion action.
    @Test("partial coverage surfaces retry and scope actions")
    func partialCoverage() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations]
        )
        backend.cachedConversationHandler = { anchor, _ in
            try Self.snapshot(
                anchor: anchor,
                members: [anchor],
                coverage: .partial,
                excludedFolderIDs: ["Junk"],
                unavailableFolderIDs: ["Archive"]
            )
        }
        let controller = try makeController()
        controller.updateAnchor(
            header: Self.header(id: "inbox-1"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()
        assertBar(controller: controller, named: "partial-coverage")
    }

    /// A failed remote lookup swaps the message for the failure copy and
    /// keeps Retry available.
    @Test("failed remote lookup shows retry")
    func failedLookupShowsRetry() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.relatedConversationLoading]
        )
        backend.relatedConversationHandler = { _, _, _, _ in
            throw ConversationLookupError.invalidSnapshot
        }
        let controller = try makeController()
        controller.updateAnchor(
            header: Self.header(id: "inbox-1"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()
        controller.loadRelatedMail()
        await controller.awaitSettled()
        assertBar(controller: controller, named: "failed-retry")
    }

    // MARK: - Fixtures

    private static let account = BrevAccount(
        id: "account-1",
        displayName: "Personal",
        emailAddress: "me@example.org"
    )
    private static let source = MailSourceID(accountID: account.id, mailboxID: "mailbox-1")

    private func makeController() throws -> RelatedConversationController {
        let name = "RelatedConversationBarSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return RelatedConversationController(
            consentStore: RelatedConversationConsentStore(defaults: defaults)
        )
    }

    private func assertBar(controller: RelatedConversationController, named name: String) {
        let theme = BrevTheme.brevSlate
        let view = RelatedConversationBar(controller: controller)
            .frame(width: 560)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 560, height: 44)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 44)),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private nonisolated static func header(id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-1",
            folderID: "INBOX",
            from: Correspondent(email: "sender@example.org"),
            to: [],
            subject: "Topic",
            snippet: "",
            date: Date(timeIntervalSince1970: 86400)
        )
    }

    private nonisolated static func snapshot(
        anchor: ConversationMember,
        members: [ConversationMember],
        coverage: ConversationCoverage = .cached,
        excludedFolderIDs: [Folder.ID] = [],
        unavailableFolderIDs: [Folder.ID] = []
    ) throws -> ConversationSnapshot {
        try ConversationSnapshot(
            anchor: anchor.location,
            members: members,
            coverage: coverage,
            excludedFolderIDs: excludedFolderIDs,
            unavailableFolderIDs: unavailableFolderIDs
        )
    }
}
#endif
