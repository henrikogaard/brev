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

@Suite("AppSessionRestoreResponsePolicy")
struct AppSessionRestoreResponsePolicyTests {
    @Test("matching active restore request can apply a restore response")
    func matchingActiveRestoreRequestCanApplyRestoreResponse() {
        #expect(AppSessionRestoreResponsePolicy.canApplyResponse(
            request: AppSessionRestoreRequest(id: 1),
            activeRequest: AppSessionRestoreRequest(id: 1)
        ))
    }

    @Test("changed or missing active restore request rejects stale restore response")
    func changedOrMissingActiveRestoreRequestRejectsStaleRestoreResponse() {
        let request = AppSessionRestoreRequest(id: 1)

        #expect(!AppSessionRestoreResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: AppSessionRestoreRequest(id: 2)
        ))
        #expect(!AppSessionRestoreResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil
        ))
    }

    @Test("mailbox root shows as soon as an account is visible during restore")
    func mailboxRootShowsAsSoonAsAccountVisibleDuringRestore() {
        // Cache-first: one connected account renders immediately, even while
        // the rest of the session is still restoring.
        #expect(AppSessionRestorePresentationPolicy.shouldShowMailboxRoot(
            visibleBackendCount: 1,
            isRestoringSession: true
        ))
        // With a backend already visible, the full-screen progress surface is
        // not shown (the mailbox root takes precedence).
        #expect(!AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
            visibleBackendCount: 1,
            isRestoringSession: true,
            sessionRestoreAttempted: false
        ))
        // With no account visible yet, the progress surface blocks until the
        // first restore completes.
        #expect(AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
            visibleBackendCount: 0,
            isRestoringSession: true,
            sessionRestoreAttempted: false
        ))
        #expect(!AppSessionRestorePresentationPolicy.shouldShowMailboxRoot(
            visibleBackendCount: 0,
            isRestoringSession: true
        ))
        // Once restore is finished with no accounts, fall through to login.
        #expect(!AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
            visibleBackendCount: 0,
            isRestoringSession: false,
            sessionRestoreAttempted: true
        ))
    }
}
