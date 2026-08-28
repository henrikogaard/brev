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

@testable import BrevBackend
import Testing

@Suite("MailBackendError")
struct MailBackendErrorTests {
    @Test("backend specific errors expose their message to the UI")
    func backendSpecificErrorsExposeMessage() {
        let error = MailBackendError.backendSpecific(message: "Configure the OAuth client ID first.")

        #expect(error.localizedDescription == "Configure the OAuth client ID first.")
    }

    @Test("common backend errors have readable descriptions")
    func commonBackendErrorsHaveReadableDescriptions() {
        #expect(MailBackendError.notConnected.localizedDescription == "Mail backend is not connected.")
        #expect(MailBackendError.authenticationRequired.localizedDescription == "Sign in again to continue.")
        #expect(MailBackendError.notFound(id: "m1").localizedDescription == "Couldn't find m1.")
        #expect(
            MailBackendError.permissionDenied(message: "Provider permission denied.").localizedDescription
                == "Provider permission denied."
        )
        #expect(MailBackendError.quotaExceeded.localizedDescription == "Mailbox quota exceeded.")
        #expect(MailBackendError.network(underlying: "offline").localizedDescription == "Network error: offline")
    }

    @Test("permanent OAuth refresh failures never queue or hide behind cache")
    func permanentOAuthRefreshFailuresDoNotUseRecoveryFallbacks() {
        #expect(!IMAPSMTPBackend.shouldQueueOfflineMutation(for: OAuthRefreshError.reauthenticationRequired))
        #expect(!IMAPSMTPBackend.shouldQueueOfflineMutation(for: OAuthRefreshError.missingRefreshToken))
        #expect(!IMAPSMTPBackend.shouldUseCacheFallback(for: OAuthRefreshError.reauthenticationRequired))
        #expect(!IMAPSMTPBackend.shouldUseCacheFallback(for: OAuthRefreshError.missingRefreshToken))
    }

    @Test("transient OAuth refresh HTTP failures remain retryable")
    func transientOAuthRefreshFailuresRemainRetryable() {
        let error = OAuthRefreshError.refreshFailed(statusCode: 503, bodyByteCount: 0)
        #expect(IMAPSMTPBackend.shouldQueueOfflineMutation(for: error))
        #expect(IMAPSMTPBackend.shouldUseCacheFallback(for: error))
    }

    @Test("backend-specific errors are surfaced instead of queued or cached")
    func backendSpecificErrorsDoNotUseOfflineRecovery() {
        let error = MailBackendError.backendSpecific(message: "Local validation failed.")
        #expect(!IMAPSMTPBackend.shouldQueueOfflineMutation(for: error))
        #expect(!IMAPSMTPBackend.shouldUseCacheFallback(for: error))
    }
}
