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

@testable import BrevMail
import Testing

@Suite("MailRootWorkBlockPolicy")
struct MailRootWorkBlockPolicyTests {
    @Test("message work is blocked while a sheet is presented")
    func messageWorkIsBlockedWhileSheetIsPresented() {
        #expect(MailRootWorkBlockPolicy.isMessageWorkBlocked(
            hasPresentedSheet: true,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil
        ))
    }

    @Test("compose work is not blocked only because its sheet is presented")
    func composeWorkIsNotBlockedOnlyBecauseItsSheetIsPresented() {
        #expect(!MailRootWorkBlockPolicy.isComposeWorkBlocked(
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil
        ))
    }

    @Test("message and compose work are blocked by active root mail work")
    func messageAndComposeWorkAreBlockedByActiveRootMailWork() {
        #expect(MailRootWorkBlockPolicy.isMessageWorkBlocked(
            hasPresentedSheet: false,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: MailRootRefreshRequest(
                id: 1,
                folderID: "inbox",
                mailboxID: "mailbox-a"
            ),
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil
        ))
        #expect(MailRootWorkBlockPolicy.isComposeWorkBlocked(
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: MailRootRefreshRequest(
                id: 1,
                folderID: "inbox",
                mailboxID: "mailbox-a"
            ),
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil
        ))
    }

    @Test("backend event refreshes defer behind active sheets")
    func backendEventRefreshesDeferBehindActiveSheets() {
        #expect(MailRootWorkBlockPolicy.shouldDeferBackendEventRefresh(
            hasPresentedSheet: true,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("backend event refreshes defer while compose completion is active")
    func backendEventRefreshesDeferWhileComposeCompletionIsActive() {
        #expect(MailRootWorkBlockPolicy.shouldDeferBackendEventRefresh(
            hasPresentedSheet: false,
            activeComposeCompletionRequest: MailRootComposeCompletionRequest(
                id: 1,
                composePresentationID: 1,
                mailboxID: "mailbox-a"
            )
        ))
    }

    @Test("backend event refreshes run when no sheet or compose completion is active")
    func backendEventRefreshesRunWhenNoSheetOrComposeCompletionIsActive() {
        #expect(!MailRootWorkBlockPolicy.shouldDeferBackendEventRefresh(
            hasPresentedSheet: false,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("stale root work recovery clears unchanged blocker without presented sheet")
    func staleRootWorkRecoveryClearsUnchangedBlockerWithoutPresentedSheet() {
        let snapshot = MailRootWorkBlockSnapshot(
            folderLoadID: nil,
            mailboxLoadID: nil,
            refreshID: nil,
            mailboxSwitchID: nil,
            commandMutationID: 7,
            composeCompletionID: nil
        )

        #expect(MailRootWorkBlockRecoveryPolicy.shouldStartWatchdog(snapshot: snapshot))
        #expect(MailRootWorkBlockRecoveryPolicy.shouldRecoverStaleWork(
            snapshotAtStart: snapshot,
            currentSnapshot: snapshot,
            hasPresentedSheet: false
        ))
    }

    @Test("stale root work recovery waits when blocker changed or sheet is presented")
    func staleRootWorkRecoveryWaitsWhenBlockerChangedOrSheetIsPresented() {
        let snapshot = MailRootWorkBlockSnapshot(
            folderLoadID: nil,
            mailboxLoadID: nil,
            refreshID: 1,
            mailboxSwitchID: nil,
            commandMutationID: nil,
            composeCompletionID: nil
        )
        let changed = MailRootWorkBlockSnapshot(
            folderLoadID: nil,
            mailboxLoadID: nil,
            refreshID: 2,
            mailboxSwitchID: nil,
            commandMutationID: nil,
            composeCompletionID: nil
        )

        #expect(!MailRootWorkBlockRecoveryPolicy.shouldRecoverStaleWork(
            snapshotAtStart: snapshot,
            currentSnapshot: changed,
            hasPresentedSheet: false
        ))
        #expect(!MailRootWorkBlockRecoveryPolicy.shouldRecoverStaleWork(
            snapshotAtStart: snapshot,
            currentSnapshot: snapshot,
            hasPresentedSheet: true
        ))
        #expect(!MailRootWorkBlockRecoveryPolicy.shouldStartWatchdog(snapshot: .empty))
    }

    @Test("stale timeout only elapses after a full window without progress")
    func staleTimeoutOnlyElapsesAfterFullWindowWithoutProgress() {
        let timeout = MailRootWorkBlockRecoveryPolicy.staleWorkTimeoutNanoseconds
        let poll = MailRootWorkBlockRecoveryPolicy.progressPollIntervalNanoseconds

        // A single poll interval (progress was just observed) is not stale.
        #expect(!MailRootWorkBlockRecoveryPolicy.hasExceededStaleTimeout(
            nanosecondsWithoutProgress: poll
        ))
        // Just under the timeout is still not stale...
        #expect(!MailRootWorkBlockRecoveryPolicy.hasExceededStaleTimeout(
            nanosecondsWithoutProgress: timeout - poll
        ))
        // ...but reaching the full window without progress is.
        #expect(MailRootWorkBlockRecoveryPolicy.hasExceededStaleTimeout(
            nanosecondsWithoutProgress: timeout
        ))
    }
}
