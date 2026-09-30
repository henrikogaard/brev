/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), including
 without limitation the rights to use, copy, modify, merge, publish, distribute,
 sublicense, and/or sell copies of the Software, subject to the conditions in the
 LICENSE file.
 */

@testable import BrevMail
import CoreGraphics
import Testing

@Suite("Login view presentation")
struct LoginViewPresentationTests {
    @Test("wide layout starts at the desktop onboarding width")
    func wideLayoutStartsAtDesktopWidth() {
        #expect(LoginViewPresentation.layout(for: 699) == .compact)
        #expect(LoginViewPresentation.layout(for: 700) == .wide)
        #expect(LoginViewPresentation.layout(for: 956) == .wide)
    }

    @Test("recovery exposes one actionable repair control")
    func recoveryExposesOneAction() {
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: "person@example.org",
                canRetry: true,
                canUseGoogleIMAPFallback: true
            ) == .googleIMAPFallback
        )
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: "person@example.org",
                canRetry: true
            ) == .updatePassword
        )
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: nil,
                canRetry: true
            ) == .retry
        )
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: nil,
                canRetry: false
            ) == nil
        )
    }

    @Test("recovery repairs a native Gmail account with Google sign-in")
    func recoveryRepairsNativeGmailAccountWithGoogleSignIn() {
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: "person@gmail.com",
                canRetry: true,
                googleReauthentication: true
            ) == .googleReauthentication
        )
        // The explicit IMAP fallback offer still wins over a fresh Google sign-in.
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: "person@gmail.com",
                canRetry: true,
                canUseGoogleIMAPFallback: true,
                googleReauthentication: true
            ) == .googleIMAPFallback
        )
        // Without a failed account the flag cannot fabricate a repair action.
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: nil,
                canRetry: true,
                googleReauthentication: true
            ) == .retry
        )
        #expect(
            LoginViewPresentation.recoveryAction(
                failedEmail: "person@example.org",
                canRetry: true,
                googleReauthentication: false
            ) == .updatePassword
        )
    }
}
