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

import AuthenticationServices
import BrevBackend
import Foundation

/// Shared OAuth2 sign-in → IMAP/SMTP provisioning flow used by both the macOS
/// and iOS app targets. Previously this was copy-pasted verbatim into each
/// `BrevApp`; only the presentation anchor differs per platform, so it's the
/// single injected parameter. Account-id derivation goes through
/// `BrevAccount.imapSMTPAccountID(forEmailAddress:)` so OAuth-token keying
/// stays consistent with provisioning.
public enum IMAPOAuthLoginFlow {
    /// Runs the shared Google browser flow, then hands the verified result to
    /// the injected account connector. The connector owns persistence and
    /// backend-specific token installation; the IMAP fallback below retains
    /// its existing token-store behavior when no connector is provided.
    @MainActor
    static func makeGoogleLoginResult(
        presentationAnchor: @MainActor () throws -> ASPresentationAnchor,
        accountProvisioner: @escaping AppSession.GoogleOAuthAccountProvisioningCoordinator
    ) async throws -> AppSession.LoginResult {
        let anchor = try presentationAnchor()
        let result = try await GoogleOAuthFlow().signIn(presentationContext: anchor)
        return try await provisionGoogleOAuthResult(result, accountProvisioner: accountProvisioner)
    }

    /// Applies the injected Google account connector to an already verified
    /// OAuth result. Keeping this seam separate makes connector behavior
    /// testable without launching a system browser.
    static func provisionGoogleOAuthResult(
        _ result: GoogleOAuthResult,
        accountProvisioner: @escaping AppSession.GoogleOAuthAccountProvisioningCoordinator
    ) async throws -> AppSession.LoginResult {
        try await accountProvisioner(result)
    }

    @MainActor
    public static func makeLoginResult(
        provider: IMAPOAuthProvider,
        connector: IMAPAccountConnector,
        tokenStore: any TokenStore,
        presentationAnchor: @MainActor () throws -> ASPresentationAnchor
    ) async throws -> AppSession.LoginResult {
        let anchor = try presentationAnchor()
        switch provider {
        case .google:
            let result = try await GoogleOAuthFlow().signIn(presentationContext: anchor)
            return try await provision(
                provider: .google,
                emailAddress: result.email,
                accessToken: result.accessToken,
                token: result.asToken(),
                connector: connector,
                tokenStore: tokenStore
            )
        case .microsoft:
            let result = try await OutlookOAuthFlow().signIn(presentationContext: anchor)
            return try await provision(
                provider: .microsoft,
                emailAddress: result.email,
                accessToken: result.accessToken,
                token: result.asToken(),
                connector: connector,
                tokenStore: tokenStore
            )
        }
    }

    private static func provision(
        provider: IMAPOAuthProvider,
        emailAddress: String,
        accessToken: String,
        token: Token,
        connector: IMAPAccountConnector,
        tokenStore: any TokenStore
    ) async throws -> AppSession.LoginResult {
        guard let profile = discoveryProfile(for: provider, emailAddress: emailAddress),
              let incoming = profile.incoming,
              let outgoing = profile.outgoing else {
            throw MailBackendError.backendSpecific(
                message: "Brev could not find OAuth IMAP/SMTP settings for this account."
            )
        }

        let accountID = BrevAccount.imapSMTPAccountID(forEmailAddress: emailAddress)
        let request = IMAPOAuthSetupRequest(
            emailAddress: emailAddress,
            incoming: incoming,
            outgoing: outgoing,
            accessToken: accessToken
        )
        return try await tokenStore.withTokenInstalled(token, for: accountID) {
            let connected = try await connector.provisionAndConnectOAuth(request)
            return AppSession.LoginResult(backend: connected.backend, account: connected.account)
        }
    }

    static func discoveryProfile(
        for provider: IMAPOAuthProvider,
        emailAddress: String
    ) -> MailAccountDiscoveryResult? {
        switch provider {
        case .google:
            return MailAccountAutodiscovery.googleProfile(forEmailAddress: emailAddress)
        case .microsoft:
            return MailAccountAutodiscovery.profile(forEmailAddress: emailAddress)
                ?? MailAccountAutodiscovery.profile(forEmailAddress: "user@outlook.com")
        }
    }
}
