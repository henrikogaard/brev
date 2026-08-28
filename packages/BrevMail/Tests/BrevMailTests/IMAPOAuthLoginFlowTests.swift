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

@Suite("IMAP OAuth login flow")
struct IMAPOAuthLoginFlowTests {
    @Test("Google selects Gmail settings for Workspace addresses")
    func googleSelectsGmailProfile() {
        let profile = IMAPOAuthLoginFlow.discoveryProfile(
            for: .google,
            emailAddress: "person@example.edu"
        )

        #expect(profile?.incoming?.host == "imap.gmail.com")
        #expect(profile?.outgoing?.host == "smtp.gmail.com")
    }

    @Test("Microsoft selects Outlook settings instead of Gmail settings")
    func microsoftSelectsMicrosoftProfile() {
        let profile = IMAPOAuthLoginFlow.discoveryProfile(
            for: .microsoft,
            emailAddress: "person@outlook.com"
        )

        #expect(profile?.incoming?.host == "outlook.office365.com")
        #expect(profile?.outgoing?.host == "smtp.office365.com")
        #expect(profile?.incoming?.host != "imap.gmail.com")
    }

    @Test("Google OAuth provisioning preserves the verified result for a native connector")
    func googleOAuthProvisioningPreservesVerifiedResult() async throws {
        let expected = GoogleOAuthResult(
            accessToken: "access",
            refreshToken: "refresh",
            email: "person@gmail.com",
            expiresAt: Date(timeIntervalSince1970: 1234)
        )
        let backend = MockBackend(
            account: BrevAccount(
                id: "gmail-api:subject",
                displayName: "Google",
                emailAddress: expected.email,
                backendIdentifier: "gmail-api",
                backendDisplayName: "Gmail"
            )
        )
        var received: GoogleOAuthResult?

        let loginResult = try await IMAPOAuthLoginFlow.provisionGoogleOAuthResult(
            expected,
            accountProvisioner: { result in
                received = result
                return AppSession.LoginResult(backend: backend, account: backend.account)
            }
        )

        #expect(received == expected)
        #expect(loginResult.account.backendIdentifier == "gmail-api")
    }

    @Test("Google OAuth provisioning propagates connector cancellation")
    func googleOAuthProvisioningPropagatesCancellation() async {
        let result = GoogleOAuthResult(
            accessToken: "access",
            refreshToken: "refresh",
            email: "person@gmail.com",
            expiresAt: Date(timeIntervalSince1970: 1234)
        )

        do {
            _ = try await IMAPOAuthLoginFlow.provisionGoogleOAuthResult(
                result,
                accountProvisioner: { _ in throw CancellationError() }
            )
            Issue.record("Expected connector cancellation")
        } catch is CancellationError {
            // Expected: AppSession treats OAuth cancellation as a quiet dismissal.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
