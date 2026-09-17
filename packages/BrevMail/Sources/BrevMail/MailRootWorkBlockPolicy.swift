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

struct MailRootWorkBlockSnapshot: Equatable, Sendable {
    static let empty = MailRootWorkBlockSnapshot(
        folderLoadID: nil,
        mailboxLoadID: nil,
        refreshID: nil,
        mailboxSwitchID: nil,
        commandMutationID: nil,
        composeCompletionID: nil
    )

    let folderLoadID: Int?
    let mailboxLoadID: Int?
    let refreshID: Int?
    let mailboxSwitchID: Int?
    let commandMutationID: Int?
    let composeCompletionID: Int?

    var hasActiveRootWork: Bool {
        folderLoadID != nil
            || mailboxLoadID != nil
            || refreshID != nil
            || mailboxSwitchID != nil
            || commandMutationID != nil
            || composeCompletionID != nil
    }
}

enum MailRootWorkBlockRecoveryPolicy {
    /// Recovery only fires after outstanding work has made *no progress* for
    /// this long. A heartbeat (backend events, operation milestones) resets the
    /// elapsed counter, so a legitimately slow-but-progressing operation no
    /// longer trips recovery — only a genuinely stuck one does.
    static let staleWorkTimeoutNanoseconds: UInt64 = 60_000_000_000

    /// How often the watchdog re-checks for progress while work is outstanding.
    static let progressPollIntervalNanoseconds: UInt64 = 5_000_000_000

    static func shouldStartWatchdog(snapshot: MailRootWorkBlockSnapshot) -> Bool {
        snapshot.hasActiveRootWork
    }

    /// True once the outstanding work has gone without any progress for the full
    /// stale timeout.
    static func hasExceededStaleTimeout(nanosecondsWithoutProgress: UInt64) -> Bool {
        nanosecondsWithoutProgress >= staleWorkTimeoutNanoseconds
    }

    static func shouldRecoverStaleWork(
        snapshotAtStart: MailRootWorkBlockSnapshot,
        currentSnapshot: MailRootWorkBlockSnapshot,
        hasPresentedSheet: Bool
    ) -> Bool {
        !hasPresentedSheet
            && snapshotAtStart.hasActiveRootWork
            && snapshotAtStart == currentSnapshot
    }
}

enum MailRootWorkBlockPolicy {
    static func hasMailContext(visibleSourceCount: Int, hasAnySources: Bool, hasFallbackFolders: Bool,
                               isAllMailboxesProfile: Bool) -> Bool {
        visibleSourceCount > 0 || (!hasAnySources && hasFallbackFolders && isAllMailboxesProfile)
    }

    static func isMessageWorkBlocked(
        hasPresentedSheet: Bool,
        activeFolderLoadRequest: MailRootFolderLoadRequest?,
        activeMailboxLoadRequest: MailRootMailboxLoadRequest?,
        activeRefreshRequest: MailRootRefreshRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        activeCommandMutationRequest: MailRootCommandMutationRequest?,
        hasUsableContent: Bool = false
    ) -> Bool {
        hasPresentedSheet || isRootMailWorkActive(
            activeFolderLoadRequest: hasUsableContent ? nil : activeFolderLoadRequest,
            activeMailboxLoadRequest: hasUsableContent ? nil : activeMailboxLoadRequest,
            activeRefreshRequest: hasUsableContent ? nil : activeRefreshRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest,
            activeCommandMutationRequest: activeCommandMutationRequest
        )
    }

    static func isComposeWorkBlocked(
        activeFolderLoadRequest: MailRootFolderLoadRequest?,
        activeMailboxLoadRequest: MailRootMailboxLoadRequest?,
        activeRefreshRequest: MailRootRefreshRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        activeCommandMutationRequest: MailRootCommandMutationRequest?
    ) -> Bool {
        isRootMailWorkActive(
            activeFolderLoadRequest: activeFolderLoadRequest,
            activeMailboxLoadRequest: activeMailboxLoadRequest,
            activeRefreshRequest: activeRefreshRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest,
            activeCommandMutationRequest: activeCommandMutationRequest
        )
    }

    static func shouldDeferBackendEventRefresh(
        hasPresentedSheet: Bool,
        activeComposeCompletionRequest: MailRootComposeCompletionRequest?
    ) -> Bool {
        hasPresentedSheet || activeComposeCompletionRequest != nil
    }

    private static func isRootMailWorkActive(
        activeFolderLoadRequest: MailRootFolderLoadRequest?,
        activeMailboxLoadRequest: MailRootMailboxLoadRequest?,
        activeRefreshRequest: MailRootRefreshRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        activeCommandMutationRequest: MailRootCommandMutationRequest?
    ) -> Bool {
        activeFolderLoadRequest != nil
            || activeMailboxLoadRequest != nil
            || activeRefreshRequest != nil
            || activeMailboxSwitchRequest != nil
            || activeCommandMutationRequest != nil
    }
}
