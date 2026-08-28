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
@testable import BrevBackend
import CryptoKit
import Foundation
import Testing

// MARK: - Helpers

private func base64URLEncode(_ string: String) -> String {
    Data(string.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Builds a minimal unsigned JWT with the given payload claims.
private func makeIDToken(claims: String) -> String {
    let header = base64URLEncode(#"{"alg":"RS256","typ":"JWT"}"#)
    let payload = base64URLEncode(claims)
    let signature = "fakesignature"
    return "\(header).\(payload).\(signature)"
}

// MARK: - Tests

@Suite("OutlookOAuthFlow")
struct OutlookOAuthFlowTests {
    @Test("missingClientID has a user-facing error description")
    func missingClientIDErrorDescription() {
        #expect(
            OutlookOAuthFlowError.missingClientID.errorDescription
                == "Microsoft sign-in is not configured in this build."
        )
    }

    @Test("signIn throws missingClientID before starting browser work")
    @MainActor
    func signInThrowsMissingClientIDBeforeBrowserWork() async {
        let flow = OutlookOAuthFlow(clientID: " \n\t")

        await #expect(throws: OutlookOAuthFlowError.missingClientID) {
            try await flow.signIn(presentationContext: ASPresentationAnchor())
        }
    }

    // MARK: Authorization URL

    @Test("authorization URL contains required OAuth2 parameters")
    @MainActor
    func authorizationURLContainsRequiredParameters() {
        let flow = OutlookOAuthFlow(clientID: "test-client")
        let url = flow.buildAuthorizationURL(state: "my-state-value")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "test-client")
        #expect(items["redirect_uri"] == OutlookOAuthFlow.redirectURI)
        #expect(items["state"] == "my-state-value")
        #expect(items["response_mode"] == "query")
        #expect(items["scope"]?.contains("offline_access") == true)
        #expect(items["scope"]?.contains("IMAP.AccessAsUser.All") == true)
    }

    @Test("authorization URL uses the Microsoft authorization endpoint")
    @MainActor
    func authorizationURLUsesMicrosoftEndpoint() {
        let flow = OutlookOAuthFlow(clientID: "cid")
        let url = flow.buildAuthorizationURL(state: "s")
        #expect(url.host == "login.microsoftonline.com")
    }

    // MARK: PKCE

    @Test("authorization URL carries a PKCE code_challenge with S256 method")
    @MainActor
    func authorizationURLContainsPKCEChallenge() {
        let flow = OutlookOAuthFlow(clientID: "cid")
        let url = flow.buildAuthorizationURL(state: "s")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(items["code_challenge_method"] == "S256")
        let challenge = items["code_challenge"]
        #expect(challenge?.isEmpty == false)
        // base64url alphabet only: no padding, no '+' or '/'.
        #expect(challenge?.contains("=") == false)
        #expect(challenge?.contains("+") == false)
        #expect(challenge?.contains("/") == false)
    }

    @Test("PKCE challenge equals base64url(sha256(verifier))")
    func pkceChallengeMatchesVerifierDigest() {
        let pair = PKCECodePair()
        let digest = SHA256.hash(data: Data(pair.verifier.utf8))
        let expected = base64URLEncode(Data(digest))
        #expect(pair.challenge == expected)
    }

    @Test("PKCE verifier is base64url-encoded 32-byte (no padding) entropy")
    func pkceVerifierIsBase64URLEncoded() {
        let pair = PKCECodePair()
        #expect(!pair.verifier.isEmpty)
        #expect(!pair.verifier.contains("="))
        #expect(!pair.verifier.contains("+"))
        #expect(!pair.verifier.contains("/"))
        // 32 random bytes base64-encode to 43 unpadded characters.
        #expect(pair.verifier.count == 43)
        // Two fresh pairs must differ — the verifier is random.
        #expect(PKCECodePair().verifier != PKCECodePair().verifier)
    }

    @Test("a fixed verifier derives a stable, known challenge")
    func pkceFixedVerifierDerivesStableChallenge() {
        // RFC 7636 Appendix B reference vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let pair = PKCECodePair(verifier: verifier)
        #expect(pair.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    // MARK: Code extraction

    @Test("extracts code from a valid callback URL")
    func extractsCodeFromValidCallback() throws {
        let url = URL(string: "brev://oauth?code=auth-code-xyz&state=expected-state")!
        let code = try OutlookOAuthFlow.extractAuthorizationCode(
            from: url,
            expectedState: "expected-state"
        )
        #expect(code == "auth-code-xyz")
    }

    @Test("throws stateMismatch when state does not match")
    func throwsOnStateMismatch() {
        let url = URL(string: "brev://oauth?code=abc&state=wrong-state")!
        #expect(throws: OutlookOAuthFlowError.stateMismatch) {
            _ = try OutlookOAuthFlow.extractAuthorizationCode(
                from: url,
                expectedState: "expected-state"
            )
        }
    }

    @Test("throws missingCodeInCallback when code is absent")
    func throwsWhenCodeAbsent() {
        let url = URL(string: "brev://oauth?state=expected-state")!
        #expect(throws: OutlookOAuthFlowError.missingCodeInCallback) {
            _ = try OutlookOAuthFlow.extractAuthorizationCode(
                from: url,
                expectedState: "expected-state"
            )
        }
    }

    @Test("throws authorizationFailed when error parameter is present")
    func throwsWhenErrorParameterPresent() {
        let url = URL(string: "brev://oauth?error=access_denied&state=expected-state")!
        do {
            _ = try OutlookOAuthFlow.extractAuthorizationCode(
                from: url,
                expectedState: "expected-state"
            )
            Issue.record("Expected an error to be thrown")
        } catch let error as OutlookOAuthFlowError {
            if case .authorizationFailed(let err, _) = error {
                #expect(err == "access_denied")
            } else {
                Issue.record("Expected authorizationFailed, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: Token response decoding

    @Test("decodes a complete token response correctly")
    func decodesCompleteTokenResponse() throws {
        let idToken = makeIDToken(
            claims: #"{"sub":"1","preferred_username":"user@outlook.com"}"#
        )
        let json = """
        {
            "access_token": "EwAo.access",
            "refresh_token": "M.refresh",
            "expires_in": 3600,
            "id_token": "\(idToken)",
            "token_type": "Bearer"
        }
        """
        let result = try OutlookOAuthFlow.decodeTokenResponse(from: Data(json.utf8))

        #expect(result.accessToken == "EwAo.access")
        #expect(result.refreshToken == "M.refresh")
        #expect(result.email == "user@outlook.com")
        #expect(result.expiresAt.timeIntervalSinceNow > 3500)
    }

    @Test("throws malformedTokenResponse when access_token is missing")
    func throwsWhenAccessTokenMissing() {
        let idToken = makeIDToken(claims: #"{"preferred_username":"a@b.com"}"#)
        let json = """
        { "refresh_token": "r", "id_token": "\(idToken)" }
        """
        #expect(throws: OutlookOAuthFlowError.self) {
            try OutlookOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        }
    }

    @Test("throws malformedTokenResponse when refresh_token is missing")
    func throwsWhenRefreshTokenMissing() {
        let idToken = makeIDToken(claims: #"{"preferred_username":"a@b.com"}"#)
        let json = """
        { "access_token": "a", "id_token": "\(idToken)" }
        """
        #expect(throws: OutlookOAuthFlowError.self) {
            try OutlookOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        }
    }

    @Test("malformed token responses keep response bodies out of the error")
    func malformedTokenResponseRedactsBody() {
        let body = #"not-json secret-token-fragment-xyz"#

        #expect(throws: OutlookOAuthFlowError.malformedTokenResponse(reason: "JSON decode error")) {
            try OutlookOAuthFlow.decodeTokenResponse(from: Data(body.utf8))
        }
    }

    @Test("throws missingEmail when id_token is absent")
    func throwsWhenIDTokenAbsent() {
        let json = """
        { "access_token": "a", "refresh_token": "r" }
        """
        #expect(throws: OutlookOAuthFlowError.self) {
            try OutlookOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        }
    }

    // MARK: Email claim extraction

    @Test("prefers preferred_username over email claim")
    func prefersPreferredUsernameClaim() throws {
        let idToken = makeIDToken(
            claims: #"{"preferred_username":"upn@contoso.com","email":"alt@contoso.com"}"#
        )
        let json = """
        {
            "access_token": "a",
            "refresh_token": "r",
            "expires_in": 60,
            "id_token": "\(idToken)"
        }
        """
        let result = try OutlookOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        #expect(result.email == "upn@contoso.com")
    }

    @Test("falls back to email claim when preferred_username is absent")
    func fallsBackToEmailClaim() throws {
        let idToken = makeIDToken(claims: #"{"sub":"42","email":"only@contoso.com"}"#)
        let json = """
        {
            "access_token": "a",
            "refresh_token": "r",
            "expires_in": 60,
            "id_token": "\(idToken)"
        }
        """
        let result = try OutlookOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        #expect(result.email == "only@contoso.com")
    }

    @Test("asToken() converts result to a Token for KeychainTokenStore")
    func asTokenConverts() throws {
        let idToken = makeIDToken(claims: #"{"preferred_username":"u@o.com"}"#)
        let json = """
        {
            "access_token": "at",
            "refresh_token": "rt",
            "expires_in": 7200,
            "id_token": "\(idToken)"
        }
        """
        let result = try OutlookOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        let token = result.asToken()

        #expect(token.accessToken == "at")
        #expect(token.refreshToken == "rt")
        #expect(token.expiresAt.timeIntervalSinceNow > 7100)
    }

    // MARK: Error redaction

    @Test("tokenExchangeFailed errorDescription does not leak the response body")
    func tokenExchangeFailedRedactsBody() {
        let secret = "secret-token-fragment-xyz"
        let error = OutlookOAuthFlowError.tokenExchangeFailed(
            statusCode: 400,
            bodyByteCount: #"{"error":"invalid_grant","access_token":"\#(secret)"}"#.utf8.count
        )
        let description = error.errorDescription ?? ""
        let value = String(describing: error)
        #expect(description.contains("400"))
        #expect(!description.contains(secret))
        #expect(!value.contains(secret))
    }
}
