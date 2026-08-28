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

/// Builds a minimal unsigned JWT with the given payload claims.
private func makeIDToken(email: String = "ignored@example.com", subject: String = "12345") -> String {
    let header = base64URLEncode(#"{"alg":"RS256","typ":"JWT"}"#)
    let payload = base64URLEncode(#"{"sub":"\#(subject)","email":"\#(email)","iss":"accounts.google.com"}"#)
    let signature = "fakesignature"
    return "\(header).\(payload).\(signature)"
}

private func makeUserInfo(
    email: String = "user@gmail.com",
    subject: String = "12345",
    verified: Bool = true,
    hostedDomain: String? = nil
) -> String {
    let hostedDomainField = hostedDomain.map { ",\"hd\":\"\($0)\"" } ?? ""
    return "{\"sub\":\"\(subject)\",\"email\":\"\(email)\",\"email_verified\":\(verified)\(hostedDomainField)}"
}

private let gmailScope = "https://mail.google.com/"

// MARK: - Tests

@Suite("GoogleOAuthFlow")
struct GoogleOAuthFlowTests {
    @Test("missingClientID has a user-facing error description")
    func missingClientIDErrorDescription() {
        #expect(
            GoogleOAuthFlowError.missingClientID.errorDescription
                == "Google sign-in is not configured in this build."
        )
    }

    @Test("signIn throws missingClientID before starting browser work")
    @MainActor
    func signInThrowsMissingClientIDBeforeBrowserWork() async {
        let flow = GoogleOAuthFlow(clientID: " \n\t", clientSecret: "secret")

        await #expect(throws: GoogleOAuthFlowError.missingClientID) {
            try await flow.signIn(presentationContext: ASPresentationAnchor())
        }
    }

    @Test("a failed sign-in retains the configured Desktop credential for retry")
    @MainActor
    func failedSignInRetainsDesktopCredentialForRetry() async throws {
        let flow = GoogleOAuthFlow(clientID: " ", clientSecret: "required-secret")

        await #expect(throws: GoogleOAuthFlowError.missingClientID) {
            try await flow.signIn(presentationContext: ASPresentationAnchor())
        }

        let request = flow.buildTokenExchangeRequest(
            code: "retry-code",
            codeVerifier: "retry-verifier",
            redirectURI: "http://127.0.0.1:49152/oauth2redirect"
        )
        let body = try #require(request.httpBody)
        let fields = try #require(
            String(data: body, encoding: .utf8)
        )
        #expect(fields.contains("client_secret=required-secret"))
    }

    // MARK: Authorization URL

    @Test("authorization URL contains required OAuth2 parameters")
    @MainActor
    func authorizationURLContainsRequiredParameters() {
        let flow = GoogleOAuthFlow(clientID: "test-client", clientSecret: "test-secret")
        let url = flow.buildAuthorizationURL(state: "my-state-value")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "test-client")
        #expect(items["redirect_uri"] == GoogleOAuthFlow.redirectURI)
        #expect(items["state"] == "my-state-value")
        #expect(items["access_type"] == "offline")
        #expect(items["prompt"] == "select_account consent")
        let scopes = Set(items["scope", default: ""].split(separator: " ").map(String.init))
        #expect(scopes == ["openid", "email", GoogleOAuthFlow.gmailScope])
        #expect(GoogleOAuthFlow.prefersEphemeralBrowserSession == false)
    }

    @Test("authorization URL uses the Google authorization endpoint")
    @MainActor
    func authorizationURLUsesGoogleEndpoint() {
        let flow = GoogleOAuthFlow(clientID: "cid", clientSecret: "csec")
        let url = flow.buildAuthorizationURL(state: "s")
        #expect(url.host == "accounts.google.com")
    }

    @Test("authorization and token exchange use the same runtime loopback redirect")
    @MainActor
    func runtimeLoopbackRedirectIsPreserved() throws {
        let redirectURI = "http://127.0.0.1:49152/oauth2redirect"
        let flow = GoogleOAuthFlow(clientID: "cid", clientSecret: "")
        let authorizationURL = flow.buildAuthorizationURL(
            state: "state",
            redirectURI: redirectURI
        )
        let authorizationItems = URLComponents(
            url: authorizationURL,
            resolvingAgainstBaseURL: false
        )?.queryItems
        let tokenRequest = flow.buildTokenExchangeRequest(
            code: "code",
            codeVerifier: "verifier",
            redirectURI: redirectURI
        )
        let tokenBody = try #require(tokenRequest.httpBody)
        let tokenItems = URLComponents(
            string: "https://localhost/?\(String(decoding: tokenBody, as: UTF8.self))"
        )?.queryItems

        #expect(authorizationItems?.first(where: { $0.name == "redirect_uri" })?.value == redirectURI)
        #expect(tokenItems?.first(where: { $0.name == "redirect_uri" })?.value == redirectURI)
    }

    #if os(macOS)
    @Test("macOS default redirect uses the loopback callback base")
    @MainActor
    func nativeRedirectUsesGoogleSupportedLoopbackBase() {
        let components = URLComponents(string: GoogleOAuthFlow.redirectURI)

        #expect(components?.scheme == "http")
        #expect(components?.host == "127.0.0.1")
        #expect(GoogleOAuthFlow.callbackScheme == "http")
    }
    #endif

    @Test("iOS configuration rejects a non reverse-DNS callback")
    func rejectsInvalidCallbackConfiguration() {
        let configuration = GoogleOAuthPlatformConfiguration(
            clientID: "desktop.apps.googleusercontent.com",
            redirectURI: "brev:/oauth2redirect",
            callbackScheme: "brev",
            platform: .iOS
        )
        #expect(!configuration.isValid)
        #expect(configuration.validationError?.contains("reverse-DNS") == true)
    }

    @Test("macOS Desktop configuration accepts the loopback callback base")
    func acceptsMacOSLoopbackCallbackConfiguration() {
        let configuration = GoogleOAuthPlatformConfiguration(
            clientID: "desktop.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1",
            callbackScheme: "http",
            platform: .macOS
        )
        #expect(configuration.isValid)
        #expect(configuration.validationError == nil)
    }

    @Test("macOS Desktop configuration rejects custom callback schemes")
    func rejectsMacOSCustomCallbackConfiguration() {
        let configuration = GoogleOAuthPlatformConfiguration(
            clientID: "desktop.apps.googleusercontent.com",
            redirectURI: "eu.brevmail.brev:/oauth2redirect",
            callbackScheme: "eu.brevmail.brev",
            platform: .macOS
        )
        #expect(!configuration.isValid)
        #expect(configuration.validationError?.contains("loopback") == true)
    }

    @Test("iOS configuration requires Google's reversed client ID callback")
    func requiresReversedIOSCallback() {
        let configuration = GoogleOAuthPlatformConfiguration(
            clientID: "123.apps.googleusercontent.com",
            redirectURI: "com.googleusercontent.apps.123:/oauth2redirect",
            callbackScheme: "eu.brevmail.brev",
            platform: .iOS
        )
        #expect(!configuration.isValid)
        #expect(configuration.validationError != nil)
    }

    // MARK: Code extraction

    @Test("extracts code from a valid callback URL")
    func extractsCodeFromValidCallback() throws {
        let url = URL(string: "eu.brevmail.brev:/oauth2redirect?code=auth-code-xyz&state=expected-state")!
        let code = try GoogleOAuthFlow.extractAuthorizationCode(
            from: url,
            expectedState: "expected-state"
        )
        #expect(code == "auth-code-xyz")
    }

    @Test("throws stateMismatch when state does not match")
    func throwsOnStateMismatch() {
        let url = URL(string: "eu.brevmail.brev:/oauth2redirect?code=abc&state=wrong-state")!
        #expect(throws: GoogleOAuthFlowError.stateMismatch) {
            _ = try GoogleOAuthFlow.extractAuthorizationCode(
                from: url,
                expectedState: "expected-state"
            )
        }
    }

    @Test("throws missingCodeInCallback when code is absent")
    func throwsWhenCodeAbsent() {
        let url = URL(string: "eu.brevmail.brev:/oauth2redirect?state=expected-state")!
        #expect(throws: GoogleOAuthFlowError.missingCodeInCallback) {
            _ = try GoogleOAuthFlow.extractAuthorizationCode(
                from: url,
                expectedState: "expected-state"
            )
        }
    }

    @Test("throws authorizationFailed when error parameter is present")
    func throwsWhenErrorParameterPresent() {
        let url = URL(string: "eu.brevmail.brev:/oauth2redirect?error=access_denied&state=expected-state")!
        do {
            _ = try GoogleOAuthFlow.extractAuthorizationCode(
                from: url,
                expectedState: "expected-state"
            )
            Issue.record("Expected an error to be thrown")
        } catch let error as GoogleOAuthFlowError {
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
        let idToken = makeIDToken(email: "user@gmail.com")
        let json = """
        {
            "access_token": "ya29.access",
            "refresh_token": "1//refresh",
            "refresh_token_expires_in": 604800,
            "expires_in": 3600,
            "id_token": "\(idToken)",
            "scope": "openid email https://mail.google.com/",
            "token_type": "Bearer"
        }
        """
        let result = try GoogleOAuthFlow.decodeTokenResponse(
            from: Data(json.utf8),
            userInfoData: Data(makeUserInfo().utf8),
            now: Date()
        )

        #expect(result.accessToken == "ya29.access")
        #expect(result.refreshToken == "1//refresh")
        #expect(result.email == "user@gmail.com")
        #expect(result.subject == "12345")
        #expect(result.hostedDomain == nil)
        #expect(result.grantedScopes == ["openid", "email", gmailScope])
        #expect(result.expiresAt.timeIntervalSinceNow > 3500)
        #expect(result.refreshTokenExpiresAt?.timeIntervalSinceNow ?? 0 > 604_700)
    }

    @Test("throws malformedTokenResponse when access_token is missing")
    func throwsWhenAccessTokenMissing() {
        let json = """
        { "refresh_token": "r", "id_token": "\(makeIDToken(email: "a@b.com"))" }
        """
        #expect(throws: GoogleOAuthFlowError.self) {
            try GoogleOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        }
    }

    @Test("throws malformedTokenResponse when refresh_token is missing")
    func throwsWhenRefreshTokenMissing() {
        let idToken = makeIDToken(email: "a@b.com")
        let json = """
        { "access_token": "a", "id_token": "\(idToken)" }
        """
        #expect(throws: GoogleOAuthFlowError.self) {
            try GoogleOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        }
    }

    @Test("malformed token responses keep response bodies out of the error")
    func malformedTokenResponseRedactsBody() {
        let body = #"not-json secret-token-fragment-xyz"#

        #expect(throws: GoogleOAuthFlowError.malformedTokenResponse(reason: "JSON decode error")) {
            try GoogleOAuthFlow.decodeTokenResponse(from: Data(body.utf8))
        }
    }

    @Test("token exchange failures retain only safe response metadata")
    func tokenExchangeFailureRedactsBody() {
        let secret = "secret-token-fragment-xyz"
        let error = GoogleOAuthFlowError.tokenExchangeFailed(
            statusCode: 400,
            providerCode: "invalid_grant",
            bodyByteCount: secret.utf8.count
        )
        let description = error.errorDescription ?? ""
        let value = String(describing: error)

        #expect(description.contains("400"))
        #expect(description.contains("invalid_grant"))
        #expect(!description.contains(secret))
        #expect(!value.contains(secret))
    }

    @Test("token exchange failures extract only known safe provider codes")
    func tokenExchangeFailureCodeIsRedacted() {
        #expect(
            GoogleOAuthFlow.safeTokenExchangeErrorCode(
                from: Data(#"{"error":"invalid_client","error_description":"secret detail"}"#.utf8)
            ) == "invalid_client"
        )
        #expect(
            GoogleOAuthFlow.safeTokenExchangeErrorCode(
                from: Data(#"{"error":"secret-token-fragment-xyz"}"#.utf8)
            ) == nil
        )
        #expect(GoogleOAuthFlow.safeTokenExchangeErrorCode(from: Data("not-json".utf8)) == nil)
    }

    @Test("token exchange failure details classify only known parameter errors")
    func tokenExchangeFailureDetailIsClassified() {
        #expect(
            GoogleOAuthFlow.safeTokenExchangeErrorDetail(
                from: Data(
                    #"{"error":"invalid_request","error_description":"Missing required parameter: client_secret"}"#.utf8
                )
            ) == "invalid_request:missing_client_secret"
        )
        #expect(
            GoogleOAuthFlow.safeTokenExchangeErrorDetail(
                from: Data(
                    #"{"error":"invalid_request","error_description":"Invalid code_verifier supplied"}"#.utf8
                )
            ) == "invalid_request:invalid_code_verifier"
        )
        #expect(
            GoogleOAuthFlow.safeTokenExchangeErrorDetail(
                from: Data(
                    #"{"error":"invalid_request","error_description":"secret-token-fragment-xyz"}"#.utf8
                )
            ) == "invalid_request"
        )
    }

    @Test("throws missingEmail when id_token is absent")
    func throwsWhenIDTokenAbsent() {
        let json = """
        { "access_token": "a", "refresh_token": "r" }
        """
        #expect(throws: GoogleOAuthFlowError.self) {
            try GoogleOAuthFlow.decodeTokenResponse(from: Data(json.utf8))
        }
    }

    @Test("asToken() converts result to a Token for KeychainTokenStore")
    func asTokenConverts() throws {
        let idToken = makeIDToken(email: "u@g.com")
        let json = """
        {
            "access_token": "at",
            "refresh_token": "rt",
            "expires_in": 7200,
            "id_token": "\(idToken)"
        }
        """
        let result = try GoogleOAuthFlow.decodeTokenResponse(
            from: Data(json.utf8),
            userInfoData: Data(makeUserInfo(email: "u@g.com").utf8)
        )
        let token = result.asToken(providerMode: .gmailAPI)

        #expect(token.accessToken == "at")
        #expect(token.refreshToken == "rt")
        #expect(token.expiresAt.timeIntervalSinceNow > 7100)
        #expect(token.oauthMetadata?.providerMode == .gmailAPI)
        #expect(token.oauthMetadata?.googleSubject == "12345")
        #expect(token.oauthMetadata?.grantedScopes.isEmpty == true)
    }

    @Test("persists token-bound Workspace identity metadata")
    func persistsWorkspaceIdentityMetadata() throws {
        let json = """
        {
            "access_token": "at",
            "refresh_token": "rt",
            "refresh_token_expires_in": 604800,
            "expires_in": 600,
            "scope": "openid email https://mail.google.com/",
            "id_token": "\(makeIDToken(subject: "workspace-subject"))"
        }
        """
        let now = Date(timeIntervalSince1970: 1000)
        let result = try GoogleOAuthFlow.decodeTokenResponse(
            from: Data(json.utf8),
            userInfoData: Data(
                makeUserInfo(
                    email: "person@ogard.no",
                    subject: "workspace-subject",
                    hostedDomain: "ogard.no"
                ).utf8
            ),
            now: now
        )

        #expect(result.subject == "workspace-subject")
        #expect(result.email == "person@ogard.no")
        #expect(result.hostedDomain == "ogard.no")
        #expect(result.expiresAt == now.addingTimeInterval(600))
        #expect(result.refreshTokenExpiresAt == now.addingTimeInterval(604_800))
        #expect(result.accountID == "gmail-api:workspace-subject")

        let tokenData = try JSONEncoder().encode(result.asToken(providerMode: .gmailAPI))
        let decodedToken = try JSONDecoder().decode(Token.self, from: tokenData)
        #expect(decodedToken.oauthMetadata?.googleSubject == "workspace-subject")
        #expect(decodedToken.oauthMetadata?.hostedDomain == "ogard.no")
        #expect(decodedToken.oauthMetadata?.providerMode == .gmailAPI)
        #expect(decodedToken.oauthMetadata?.grantedScopes == ["openid", "email", gmailScope])
        #expect(decodedToken.refreshTokenExpiresAt == now.addingTimeInterval(604_800))
    }

    @Test("old token records decode without OAuth metadata")
    func oldTokenRecordsRemainReadable() throws {
        let json = """
        {
            "accessToken": "old-access",
            "refreshToken": "old-refresh",
            "expiresAt": 1000
        }
        """
        let token = try JSONDecoder().decode(Token.self, from: Data(json.utf8))
        #expect(token.accessToken == "old-access")
        #expect(token.refreshToken == "old-refresh")
        #expect(token.oauthMetadata == nil)
    }

    @Test("provider configuration derives the stable Gmail API account id")
    func gmailAPIAccountConfiguration() throws {
        let configuration = GoogleOAuthAccountConfiguration(
            subject: "  workspace-subject ",
            email: "person@ogard.no",
            hostedDomain: "ogard.no",
            grantedScopes: [gmailScope],
            platform: .macOS,
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1000),
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 2000)
        )
        #expect(configuration.accountID == "gmail-api:workspace-subject")
        #expect(configuration.providerMode == .gmailAPI)

        let decoded = try JSONDecoder().decode(
            GoogleOAuthAccountConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )
        #expect(decoded == configuration)
    }

    @Test("old provider configuration decodes as IMAP fallback")
    func oldProviderConfigurationRemainsReadable() throws {
        let json = """
        {
            "email": "old@gmail.com",
            "subject": "old-subject",
            "grantedScopes": []
        }
        """
        let configuration = try JSONDecoder().decode(
            GoogleOAuthAccountConfiguration.self,
            from: Data(json.utf8)
        )
        #expect(configuration.providerMode == .imapSMTP)
        #expect(configuration.accountID == "imap-smtp:old@gmail.com")
    }

    @Test("uses token-bound verified UserInfo email instead of unsigned JWT email")
    func usesVerifiedUserInfoEmail() throws {
        let idToken = makeIDToken(email: "attacker@example.com")
        let json = """
        { "access_token": "at", "refresh_token": "rt", "id_token": "\(idToken)" }
        """
        let result = try GoogleOAuthFlow.decodeTokenResponse(
            from: Data(json.utf8),
            userInfoData: Data(makeUserInfo(email: "verified@gmail.com").utf8)
        )
        #expect(result.email == "verified@gmail.com")
    }

    @Test("rejects a forged or mismatched JWT subject")
    func rejectsMismatchedIDTokenSubject() {
        let json = """
        { "access_token": "at", "refresh_token": "rt", "id_token": "\(makeIDToken(subject: "forged-subject"))" }
        """
        #expect(throws: GoogleOAuthFlowError.identityMismatch) {
            try GoogleOAuthFlow.decodeTokenResponse(
                from: Data(json.utf8),
                userInfoData: Data(makeUserInfo(subject: "12345").utf8)
            )
        }
    }

    @Test("rejects an unverified UserInfo email")
    func rejectsUnverifiedUserInfoEmail() {
        let json = """
        { "access_token": "at", "refresh_token": "rt", "id_token": "\(makeIDToken())" }
        """
        #expect(throws: GoogleOAuthFlowError.self) {
            try GoogleOAuthFlow.decodeTokenResponse(
                from: Data(json.utf8),
                userInfoData: Data(makeUserInfo(verified: false).utf8)
            )
        }
    }

    @Test("UserInfo failures retain status and redact body")
    func userInfoFailureRedactsBody() {
        let secret = "refresh-token-fragment"
        let error = GoogleOAuthFlowError.userInfoRequestFailed(
            statusCode: 401,
            bodyByteCount: secret.utf8.count
        )
        #expect((error.errorDescription ?? "").contains("401"))
        #expect(!(error.errorDescription ?? "").contains(secret))
        #expect(!String(describing: error).contains(secret))
    }

    #if os(macOS)
    @Test("loopback cancellation maps to user cancellation")
    @MainActor
    func loopbackCancellationMapsToUserCancellation() {
        let error = GoogleOAuthFlow.mapLoopbackReceiverError(
            GoogleOAuthLoopbackReceiverError.cancelled
        )

        #expect(error as? GoogleOAuthFlowError == .userCancelled)
    }
    #endif
}
