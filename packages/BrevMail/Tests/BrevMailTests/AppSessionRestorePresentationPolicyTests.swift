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

@Suite("AppSessionRestorePresentationPolicy")
struct AppSessionRestorePresentationPolicyTests {
    @Test("reader command scenes take precedence over shared Settings presentation")
    func readerCommandPrecedesSettings() {
        #expect(!AppSessionRestorePresentationPolicy.shouldShowSettings(isRequested: true, hasReaderCommandHandoff: true))
        #expect(AppSessionRestorePresentationPolicy.shouldShowSettings(isRequested: true, hasReaderCommandHandoff: false))
        #expect(!AppSessionRestorePresentationPolicy.shouldShowSettings(isRequested: false, hasReaderCommandHandoff: false))
    }

    @Test("mailbox root shows once any backend is visible, even while restoring")
    func mailboxRootShowsOnceAnyBackendIsVisible() {
        #expect(AppSessionRestorePresentationPolicy.shouldShowMailboxRoot(
            visibleBackendCount: 1,
            isRestoringSession: true
        ))
        #expect(!AppSessionRestorePresentationPolicy.shouldShowMailboxRoot(
            visibleBackendCount: 0,
            isRestoringSession: true
        ))
    }

    @Test("full-screen progress blocks only before any backend is visible")
    func progressBlocksOnlyBeforeFirstBackend() {
        #expect(AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
            visibleBackendCount: 0,
            isRestoringSession: true,
            sessionRestoreAttempted: false
        ))
        #expect(AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
            visibleBackendCount: 0,
            isRestoringSession: false,
            sessionRestoreAttempted: false
        ))
        #expect(!AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
            visibleBackendCount: 0,
            isRestoringSession: false,
            sessionRestoreAttempted: true
        ))
        #expect(!AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
            visibleBackendCount: 2,
            isRestoringSession: true,
            sessionRestoreAttempted: false
        ))
    }

    @Test("restore errors raise the alert even when no backend remains visible")
    func restoreErrorsAlertEvenWithNoVisibleBackends() {
        #expect(AppSessionRestorePresentationPolicy.shouldShowRestoreErrorAlert(
            accountRestoreErrorCount: 2
        ))
        #expect(AppSessionRestorePresentationPolicy.shouldShowRestoreErrorAlert(
            accountRestoreErrorCount: 1
        ))
        #expect(!AppSessionRestorePresentationPolicy.shouldShowRestoreErrorAlert(
            accountRestoreErrorCount: 0
        ))
    }
}
