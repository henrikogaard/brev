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
import Testing

/// The macOS related-conversation bar stays quiet until there is something to
/// say or do: no sentence for the plain cached or complete states, and the
/// Spam and Trash action only once a lookup has produced a result.
@Suite("Related conversation bar presentation")
struct RelatedConversationBarPresentationTests {
    private func presentation(
        canLoadRelated: Bool = true,
        isLoadingRemote: Bool = false,
        remoteLoadDidFail: Bool = false,
        remoteLoadAttempted: Bool = false,
        coverage: ConversationCoverage? = nil,
        hasExcludedFolders: Bool = false,
        includesSpamAndTrash: Bool = false
    ) -> RelatedConversationBarPresentation {
        RelatedConversationBarPresentation(
            canLoadRelated: canLoadRelated,
            isLoadingRemote: isLoadingRemote,
            remoteLoadDidFail: remoteLoadDidFail,
            remoteLoadAttempted: remoteLoadAttempted,
            coverage: coverage,
            hasExcludedFolders: hasExcludedFolders,
            includesSpamAndTrash: includesSpamAndTrash
        )
    }

    @Test("an untouched cached conversation shows only Load related mail, no sentence")
    func idleOffersOnlyTheLoadAction() {
        let value = presentation(coverage: .cached, hasExcludedFolders: true)
        #expect(value.status == nil)
        #expect(value.actions == [.loadRelatedMail])
    }

    @Test("a cached conversation that cannot load remotely shows no bar")
    func cachedWithoutRemoteIsEmpty() {
        let value = presentation(canLoadRelated: false, coverage: .cached, hasExcludedFolders: true)
        #expect(value.isEmpty)
    }

    @Test("no snapshot and no remote support shows no bar")
    func nothingToShowIsEmpty() {
        #expect(presentation(canLoadRelated: false).isEmpty)
    }

    @Test("a completed lookup stays silent and offers Spam and Trash when excluded")
    func completeOffersScopeOnly() {
        let value = presentation(
            remoteLoadAttempted: true,
            coverage: .completeForScope,
            hasExcludedFolders: true
        )
        #expect(value.status == nil)
        #expect(value.actions == [.includeSpamAndTrash])
    }

    @Test("a completed lookup with nothing excluded shows no bar")
    func completeWithoutExclusionsIsEmpty() {
        let value = presentation(remoteLoadAttempted: true, coverage: .completeForScope)
        #expect(value.isEmpty)
    }

    @Test("Spam and Trash disappears once it is included")
    func includedScopeHidesTheAction() {
        let value = presentation(
            remoteLoadAttempted: true,
            coverage: .completeForScope,
            hasExcludedFolders: true,
            includesSpamAndTrash: true
        )
        #expect(value.isEmpty)
    }

    @Test("partial coverage reports it and offers Retry then Spam and Trash")
    func partialShowsStatusAndActions() {
        let value = presentation(
            canLoadRelated: false,
            coverage: .partial,
            hasExcludedFolders: true
        )
        #expect(value.status == .partial)
        #expect(value.actions == [.retry, .includeSpamAndTrash])
    }

    @Test("loading shows progress and no actions")
    func loadingHidesActions() {
        let value = presentation(
            isLoadingRemote: true,
            remoteLoadAttempted: true,
            coverage: .loading,
            hasExcludedFolders: true
        )
        #expect(value.status == .loading)
        #expect(value.actions.isEmpty)
    }

    @Test("a failed lookup reports it and offers Retry and Load related mail again")
    func failedShowsRetry() {
        let value = presentation(remoteLoadDidFail: true, remoteLoadAttempted: true)
        #expect(value.status == .failed)
        #expect(value.actions == [.retry, .loadRelatedMail])
    }
}
