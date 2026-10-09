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

import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("RelatedConversationReaderPresentation")
struct RelatedConversationReaderPresentationTests {
    private func presentation(
        canLoadRelated: Bool = true,
        isLoadingRemote: Bool = false,
        remoteLoadDidFail: Bool = false,
        remoteLoadAttempted: Bool = false,
        coverage: ConversationCoverage? = nil,
        hasExcludedFolders: Bool = false,
        includesSpamAndTrash: Bool = false
    ) -> RelatedConversationReaderPresentation {
        RelatedConversationReaderPresentation(
            canLoadRelated: canLoadRelated,
            isLoadingRemote: isLoadingRemote,
            remoteLoadDidFail: remoteLoadDidFail,
            remoteLoadAttempted: remoteLoadAttempted,
            coverage: coverage,
            hasExcludedFolders: hasExcludedFolders,
            includesSpamAndTrash: includesSpamAndTrash
        )
    }

    @Test("an unattempted lookup offers Load related mail and no footnote")
    func untouchedOffersLoad() {
        let value = presentation(coverage: .cached)
        #expect(value.menuItems == [.loadRelatedMail])
        #expect(value.status == nil)
    }

    @Test("the plain cached state without remote support shows nothing")
    func cachedWithoutRemoteIsSilent() {
        let value = presentation(canLoadRelated: false, coverage: .cached)
        #expect(value.menuItems.isEmpty)
        #expect(value.status == nil)
    }

    @Test("loading hides every action and shows the loading footnote")
    func loadingShowsFootnoteOnly() {
        let value = presentation(isLoadingRemote: true, remoteLoadAttempted: true, coverage: .loading)
        #expect(value.menuItems.isEmpty)
        #expect(value.status == .loading)
    }

    @Test("a failed lookup offers Load and Retry and reports the failure")
    func failedOffersRetry() {
        let value = presentation(remoteLoadDidFail: true, remoteLoadAttempted: true)
        #expect(value.menuItems == [.loadRelatedMail, .retry])
        #expect(value.status == .failed)
    }

    @Test("partial coverage offers Retry and Spam and Trash inclusion")
    func partialOffersRetryAndScope() {
        let value = presentation(
            remoteLoadAttempted: true,
            coverage: .partial,
            hasExcludedFolders: true
        )
        #expect(value.menuItems == [.retry, .includeSpamAndTrash])
        #expect(value.status == .partial)
    }

    @Test("complete coverage stays quiet but keeps the scope action")
    func completeForScope() {
        let value = presentation(
            remoteLoadAttempted: true,
            coverage: .completeForScope,
            hasExcludedFolders: true
        )
        #expect(value.menuItems == [.includeSpamAndTrash])
        #expect(value.status == nil)
    }

    @Test("including Spam and Trash removes the scope action")
    func scopeActionDisappearsOnceIncluded() {
        let value = presentation(
            remoteLoadAttempted: true,
            coverage: .completeForScope,
            hasExcludedFolders: true,
            includesSpamAndTrash: true
        )
        #expect(value.menuItems.isEmpty)
    }
}

@Suite("RelatedConversationReaderPresentation from controller", .serialized)
@MainActor
struct RelatedConversationReaderControllerPresentationTests {
    private static let account = BrevAccount(
        id: "account-1",
        displayName: "Personal",
        emailAddress: "me@example.org"
    )
    private static let source = MailSourceID(accountID: account.id, mailboxID: "mailbox-1")

    private func makeController() throws -> RelatedConversationController {
        let name = "RelatedConversationReaderPresentationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return RelatedConversationController(
            consentStore: RelatedConversationConsentStore(defaults: defaults)
        )
    }

    private func header(id: String) -> MessageHeader {
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

    @Test("a failing remote lookup surfaces the failed footnote and Retry")
    func failedLookup() async throws {
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.relatedConversationLoading]
        )
        backend.relatedConversationHandler = { _, _, _, _ in
            throw ConversationLookupError.invalidSnapshot
        }
        let controller = try makeController()
        controller.updateAnchor(header: header(id: "a"), sourceID: Self.source, backend: backend)
        await controller.awaitSettled()

        let before = RelatedConversationReaderPresentation(controller: controller)
        #expect(before.menuItems == [.loadRelatedMail])
        #expect(before.status == nil)

        controller.loadRelatedMail()
        await controller.awaitSettled()

        let after = RelatedConversationReaderPresentation(controller: controller)
        #expect(after.menuItems == [.loadRelatedMail, .retry])
        #expect(after.status == .failed)
    }
}
