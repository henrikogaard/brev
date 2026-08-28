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
import Foundation

// MARK: - Google OAuth2 flow errors

/// Errors produced by `GoogleOAuthFlow`.
public enum GoogleOAuthFlowError: Error, Sendable, Equatable, LocalizedError {
    /// The build does not contain a Google OAuth client ID.
    case missingClientID
    /// The build contains an invalid platform-specific callback configuration.
    case invalidConfiguration(reason: String)
    /// The user cancelled the sign-in sheet.
    case userCancelled
    /// The authorization callback URL did not contain the expected `code` parameter.
    case missingCodeInCallback
    /// The server returned an `error` parameter in the callback.
    case authorizationFailed(error: String, description: String?)
    /// The `state` parameter in the callback did not match the one we sent.
    case stateMismatch
    /// The token exchange HTTP call returned a non-200 status. Only the
    /// response status, allowlisted provider code, and body byte count are
    /// retained; the body can contain token or credential fragments.
    case tokenExchangeFailed(statusCode: Int, providerCode: String?, bodyByteCount: Int)
    /// The token response could not be decoded.
    case malformedTokenResponse(reason: String)
    /// Google rejected the token-bound UserInfo request.
    case userInfoRequestFailed(statusCode: Int, bodyByteCount: Int)
    /// The token-bound UserInfo response could not be decoded or was not verified.
    case malformedUserInfoResponse(reason: String)
    /// The id_token subject did not match the token-bound UserInfo subject.
    case identityMismatch
    /// The token response did not contain a usable verified email identity.
    case missingEmail
    /// The presentation anchor was unavailable.
    case presentationContextUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return String(localized: "Google sign-in is not configured in this build.", bundle: .module)
        case .invalidConfiguration(let reason):
            return String(localized: "Google sign-in has an invalid callback configuration: \(reason)", bundle: .module)
        case .userCancelled:
            return String(localized: "Google sign-in was cancelled.", bundle: .module)
        case .missingCodeInCallback:
            return String(localized: "Google did not return an authorization code.", bundle: .module)
        case .authorizationFailed(let error, let description):
            let detail = description.map { ": \($0)" } ?? ""
            return String(localized: "Google rejected sign-in (\(error))\(detail)", bundle: .module)
        case .stateMismatch:
            return String(localized: "Google sign-in returned an unexpected security state.", bundle: .module)
        case .tokenExchangeFailed(let code, let providerCode, _):
            // The raw body is intentionally omitted: it can contain token or
            // credential fragments (ADR-0006 forbids secrets in error output).
            let providerDetail = providerCode.map { " (\($0))" } ?? ""
            return String(
                localized: "Google rejected the token exchange\(providerDetail) (HTTP \(code)).",
                bundle: .module
            )
        case .malformedTokenResponse(let reason):
            return String(localized: "Google returned an unreadable token response: \(reason)", bundle: .module)
        case .userInfoRequestFailed(let code, _):
            return String(localized: "Google could not verify the signed-in account (HTTP \(code)).", bundle: .module)
        case .malformedUserInfoResponse(let reason):
            return String(localized: "Google returned an unreadable account profile: \(reason)", bundle: .module)
        case .identityMismatch:
            return String(localized: "Google returned inconsistent account identity data.", bundle: .module)
        case .missingEmail:
            return String(localized: "Google did not return a verified email address.", bundle: .module)
        case .presentationContextUnavailable:
            return String(localized: "Brev could not open the Google sign-in sheet.", bundle: .module)
        }
    }
}

// MARK: - OAuth result

/// The result of a completed Google OAuth2 authorization flow.
public struct GoogleOAuthResult: Sendable, Hashable {
    /// A short-lived OAuth2 Bearer access token for IMAP/SMTP XOAUTH2.
    public let accessToken: String
    /// A long-lived token used to obtain new access tokens via `OAuthTokenRefresher`.
    public let refreshToken: String
    /// The Google account's verified email address from the token-bound profile.
    public let email: String
    /// Stable Google OIDC subject from the token-bound UserInfo response.
    public let subject: String
    /// Verified Workspace hosted domain, when supplied by UserInfo.
    public let hostedDomain: String?
    /// OAuth scopes actually granted by Google.
    public let grantedScopes: Set<String>
    /// When the access token expires.
    public let expiresAt: Date
    /// When the refresh token expires, when Google supplied that metadata.
    public let refreshTokenExpiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String,
        email: String,
        expiresAt: Date,
        subject: String = "",
        hostedDomain: String? = nil,
        grantedScopes: Set<String> = [],
        refreshTokenExpiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostedDomain = Self.normaliseOptional(hostedDomain)
        self.grantedScopes = Set(
            grantedScopes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        self.expiresAt = expiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    /// Stable account key when this result contains a verified Google subject.
    public var accountID: String? {
        guard !subject.isEmpty else { return nil }
        return BrevAccount.gmailAPIAccountID(forGoogleSubject: subject)
    }

    /// Converts this result into a `Token` for use with `TokenStore`.
    public func asToken(providerMode: GoogleOAuthProviderMode = .imapSMTP) -> Token {
        Token(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            oauthMetadata: subject.isEmpty && hostedDomain == nil && grantedScopes.isEmpty && providerMode == .imapSMTP
                ? nil
                : OAuthTokenMetadata(
                    providerMode: providerMode,
                    googleSubject: subject.isEmpty ? nil : subject,
                    hostedDomain: hostedDomain,
                    grantedScopes: grantedScopes
                )
        )
    }

    private static func normaliseOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalised = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalised.isEmpty ? nil : normalised
    }
}

// MARK: - Google OAuth2 flow

/// Drives the interactive Google sign-in flow using `ASWebAuthenticationSession`.
///
/// Cross-platform (macOS + iOS). The flow:
/// 1. Build the Google OAuth2 authorization URL with IMAP/SMTP scopes.
/// 2. On macOS, start an ephemeral loopback listener; then open the native web
///    session anchored on the caller-supplied window.
/// 3. Exchange the returned `code` for access + refresh tokens.
/// 4. Verify the account through Google's token-bound OpenID UserInfo endpoint.
///
/// The callback is selected from the platform-specific public client
/// configuration. macOS Desktop clients use an ephemeral `127.0.0.1` port;
/// iOS uses Google's reversed-client-ID custom scheme.
@MainActor
public final class GoogleOAuthFlow {
    /// The Google OAuth2 authorization endpoint.
    public static let authorizationEndpoint = URL(
        string: "https://accounts.google.com/o/oauth2/v2/auth"
    )!
    /// The Google OAuth2 token endpoint.
    public static let tokenEndpoint = URL(
        string: "https://oauth2.googleapis.com/token"
    )!
    /// The token-bound OpenID Connect profile endpoint used to verify identity.
    public static let userInfoEndpoint = URL(
        string: "https://openidconnect.googleapis.com/v1/userinfo"
    )!
    /// The default redirect URI for this build's native Google OAuth client.
    public static let redirectURI = GoogleOAuthRedirectURI
    /// The default callback scheme. Must match `redirectURI`.
    public static let callbackScheme = GoogleOAuthCallbackScheme
    /// IMAP/SMTP full-access scope required for XOAUTH2 (RFC 7628).
    public static let gmailScope = "https://mail.google.com/"
    /// Reuse the system browser session so Google account SSO remains available.
    static let prefersEphemeralBrowserSession = false

    private let clientID: String
    private let redirectURI: String
    private let callbackScheme: String
    /// Google client credential used when the selected client type requires
    /// one. The macOS Desktop value is non-confidential in a native bundle;
    /// when supplied it is retained for the flow instance so a later sign-in
    /// attempt uses the same configured credential.
    private let clientSecret: String
    private let urlSession: URLSession
    private var pendingSession: ASWebAuthenticationSession?
    private var pendingPresentationProvider: AnchorPresentationProvider?

    /// Creates a flow instance.
    ///
    /// - Parameters:
    ///   - clientID: The Google OAuth2 client ID. Defaults to `GoogleOAuthClientID`.
    ///   - clientSecret: The Google OAuth2 client secret. Defaults to `GoogleOAuthClientSecret`.
    ///   - urlSession: The URLSession to use for token exchange. Defaults to `.shared`.
    public init(
        clientID: String = GoogleOAuthClientID,
        clientSecret: String = GoogleOAuthClientSecret,
        redirectURI: String = GoogleOAuthRedirectURI,
        callbackScheme: String = GoogleOAuthCallbackScheme,
        urlSession: URLSession = .shared
    ) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.redirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        self.callbackScheme = callbackScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
    }

    // MARK: - Public interface

    /// Run the interactive Google sign-in flow from start to finish.
    ///
    /// Presents a system web sheet anchored on `presentationContext`, completes
    /// the code exchange, and returns the resulting tokens and email address.
    ///
    /// - Parameter presentationContext: The window to anchor the web sheet on.
    /// - Returns: A `GoogleOAuthResult` containing the access token, refresh
    ///   token, email, and expiry.
    /// - Throws: `GoogleOAuthFlowError` on cancellation, server rejection, or
    ///   decode failure.
    public func signIn(
        presentationContext: ASPresentationAnchor
    ) async throws -> GoogleOAuthResult {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleOAuthFlowError.missingClientID
        }
        let platform = OAuthClientConfiguration.shared.googleOAuthConfiguration.platform
        let configuration = GoogleOAuthPlatformConfiguration(
            clientID: clientID,
            redirectURI: redirectURI,
            callbackScheme: callbackScheme,
            platform: platform
        )
        guard configuration.isValid else {
            throw GoogleOAuthFlowError.invalidConfiguration(
                reason: configuration.validationError ?? "unknown configuration error"
            )
        }
        let state = UUID().uuidString
        // Generate the PKCE pair at auth-URL-build time and carry the verifier
        // through to the token exchange for this same flow instance (RFC 7636).
        let pkce = PKCECodePair()
        let effectiveRedirectURI: String
        let callbackURL: URL
        #if os(macOS)
        if platform == .macOS {
            let receiver = GoogleOAuthLoopbackReceiver()
            do {
                effectiveRedirectURI = try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    return try await receiver.start()
                } onCancel: {
                    Task { @MainActor in receiver.cancel() }
                }
            } catch {
                throw Self.mapLoopbackReceiverError(error)
            }
            defer { receiver.cancel() }
            let authURL = buildAuthorizationURL(
                state: state,
                pkce: pkce,
                redirectURI: effectiveRedirectURI
            )
            callbackURL = try await runLoopbackWebAuthSession(
                authorizationURL: authURL,
                presentationContext: presentationContext,
                receiver: receiver
            )
        } else {
            effectiveRedirectURI = redirectURI
            let authURL = buildAuthorizationURL(state: state, pkce: pkce)
            callbackURL = try await runWebAuthSession(
                authorizationURL: authURL,
                callbackURLScheme: callbackScheme,
                presentationContext: presentationContext
            )
        }
        #else
        effectiveRedirectURI = redirectURI
        let authURL = buildAuthorizationURL(state: state, pkce: pkce)
        callbackURL = try await runWebAuthSession(
            authorizationURL: authURL,
            callbackURLScheme: callbackScheme,
            presentationContext: presentationContext
        )
        #endif

        let code = try Self.extractAuthorizationCode(from: callbackURL, expectedState: state)
        return try await exchangeCodeForTokens(
            code: code,
            codeVerifier: pkce.verifier,
            redirectURI: effectiveRedirectURI
        )
    }

    // MARK: - Authorization URL

    func buildAuthorizationURL(
        state: String,
        pkce: PKCECodePair = PKCECodePair(),
        redirectURI: String? = nil
    ) -> URL {
        let effectiveRedirectURI = redirectURI ?? self.redirectURI
        var components = URLComponents(
            url: Self.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: effectiveRedirectURI),
            // `openid` is required for Google's id_token, which carries the
            // account email used to provision the IMAP/SMTP account.
            URLQueryItem(name: "scope", value: "openid email \(Self.gmailScope)"),
            URLQueryItem(name: "state", value: state),
            // PKCE: bind the authorization code to this client (RFC 7636).
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Explicit account choice preserves multi-account SSO while consent
            // ensures Google issues a refresh token for this authorization.
            URLQueryItem(name: "prompt", value: "select_account consent"),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        return components.url!
    }

    // MARK: - ASWebAuthenticationSession

    private func runWebAuthSession(
        authorizationURL: URL,
        callbackURLScheme: String?,
        presentationContext: ASPresentationAnchor
    ) async throws -> URL {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: callbackURLScheme
                ) { [weak self] callbackURL, error in
                    self?.pendingSession = nil
                    self?.pendingPresentationProvider = nil
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionErrorDomain
                            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            continuation.resume(throwing: GoogleOAuthFlowError.userCancelled)
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: GoogleOAuthFlowError.missingCodeInCallback)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
                let provider = AnchorPresentationProvider(anchor: presentationContext)
                session.presentationContextProvider = provider
                // Reuse system browser cookies so an existing Google session
                // can provide SSO while Google still asks the user to choose.
                session.prefersEphemeralWebBrowserSession = Self.prefersEphemeralBrowserSession
                pendingSession = session
                pendingPresentationProvider = provider
                if !session.start() {
                    pendingSession = nil
                    pendingPresentationProvider = nil
                    continuation.resume(
                        throwing: GoogleOAuthFlowError.presentationContextUnavailable
                    )
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingWebSession()
            }
        }
    }

    #if os(macOS)
    static func mapLoopbackReceiverError(_ error: any Error) -> any Error {
        if error as? GoogleOAuthLoopbackReceiverError == .cancelled {
            return GoogleOAuthFlowError.userCancelled
        }
        return error
    }

    private func runLoopbackWebAuthSession(
        authorizationURL: URL,
        presentationContext: ASPresentationAnchor,
        receiver: GoogleOAuthLoopbackReceiver
    ) async throws -> URL {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let completion = GoogleOAuthWebSessionCompletion(continuation: continuation)
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: nil
                ) { [weak self] callbackURL, error in
                    Task { @MainActor in
                        self?.pendingSession = nil
                        self?.pendingPresentationProvider = nil
                        if let callbackURL {
                            completion.resume(returning: callbackURL)
                        } else if let error {
                            let nsError = error as NSError
                            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                                completion.resume(throwing: GoogleOAuthFlowError.userCancelled)
                            } else {
                                completion.resume(throwing: error)
                            }
                        } else {
                            completion.resume(throwing: GoogleOAuthFlowError.missingCodeInCallback)
                        }
                    }
                }
                let provider = AnchorPresentationProvider(anchor: presentationContext)
                session.presentationContextProvider = provider
                session.prefersEphemeralWebBrowserSession = Self.prefersEphemeralBrowserSession
                pendingSession = session
                pendingPresentationProvider = provider

                Task { @MainActor [weak self] in
                    do {
                        let callbackURL = try await receiver.waitForCallback()
                        guard completion.resume(returning: callbackURL) else { return }
                        self?.pendingSession = nil
                        self?.pendingPresentationProvider = nil
                        session.cancel()
                    } catch {
                        guard completion.resume(
                            throwing: Self.mapLoopbackReceiverError(error)
                        ) else { return }
                        self?.pendingSession = nil
                        self?.pendingPresentationProvider = nil
                        session.cancel()
                    }
                }

                if !session.start() {
                    pendingSession = nil
                    pendingPresentationProvider = nil
                    receiver.cancel()
                    completion.resume(throwing: GoogleOAuthFlowError.presentationContextUnavailable)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                receiver.cancel()
                self?.cancelPendingWebSession()
            }
        }
    }
    #endif

    private func cancelPendingWebSession() {
        pendingSession?.cancel()
        pendingSession = nil
        pendingPresentationProvider = nil
    }

    // MARK: - Code extraction

    nonisolated static func extractAuthorizationCode(
        from url: URL,
        expectedState: String
    ) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthFlowError.missingCodeInCallback
        }
        let items = components.queryItems ?? []

        let receivedState = items.first(where: { $0.name == "state" })?.value
        guard receivedState == expectedState else {
            throw GoogleOAuthFlowError.stateMismatch
        }

        if let error = items.first(where: { $0.name == "error" })?.value,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GoogleOAuthFlowError.authorizationFailed(
                error: error,
                description: items.first(where: { $0.name == "error_description" })?.value
            )
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleOAuthFlowError.missingCodeInCallback
        }
        return code
    }

    // MARK: - Token exchange

    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> GoogleOAuthResult {
        let request = buildTokenExchangeRequest(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI
        )

        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard statusCode == 200 else {
            throw GoogleOAuthFlowError.tokenExchangeFailed(
                statusCode: statusCode,
                providerCode: Self.safeTokenExchangeErrorDetail(from: data),
                bodyByteCount: data.count
            )
        }

        let userInfoData = try await fetchUserInfo(accessToken: responseAccessToken(from: data))
        return try Self.decodeTokenResponse(from: data, userInfoData: userInfoData)
    }

    nonisolated static func safeTokenExchangeErrorCode(from data: Data) -> String? {
        struct ErrorResponse: Decodable { let error: String }
        let allowedCodes: Set<String> = [
            "access_denied",
            "invalid_client",
            "invalid_dpop_proof",
            "invalid_grant",
            "invalid_request",
            "redirect_uri_mismatch",
            "unauthorized_client",
            "unsupported_grant_type",
            "use_dpop_nonce",
        ]
        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
              allowedCodes.contains(response.error)
        else { return nil }
        return response.error
    }

    nonisolated static func safeTokenExchangeErrorDetail(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: String
            let error_description: String?
        }
        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
              let safeCode = safeTokenExchangeErrorCode(from: data)
        else { return nil }
        guard safeCode == "invalid_request",
              let description = response.error_description?.lowercased()
        else { return safeCode }

        if description.contains("client_secret") {
            return "invalid_request:missing_client_secret"
        }
        if description.contains("code_verifier") || description.contains("code verifier") {
            return "invalid_request:invalid_code_verifier"
        }
        if description.contains("redirect_uri") || description.contains("redirect uri") {
            return "invalid_request:invalid_redirect_uri"
        }
        return safeCode
    }

    func buildTokenExchangeRequest(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) -> URLRequest {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        var body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            // PKCE: prove possession of the verifier matching the sent
            // code_challenge (RFC 7636).
            "code_verifier": codeVerifier
        ]
        // Public clients prefer PKCE over a client secret; only send the
        // secret when one is configured (Google still requires it for
        // "Web application" client types).
        if !clientSecret.isEmpty {
            body["client_secret"] = clientSecret
        }
        request.httpBody = formEncode(body)
        return request
    }

    private func responseAccessToken(from data: Data) throws -> String {
        struct TokenResponse: Decodable { let access_token: String }
        do {
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard !response.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GoogleOAuthFlowError.malformedTokenResponse(reason: "missing access_token")
            }
            return response.access_token
        } catch let error as GoogleOAuthFlowError {
            throw error
        } catch {
            throw GoogleOAuthFlowError.malformedTokenResponse(reason: "JSON decode error")
        }
    }

    private func fetchUserInfo(accessToken: String) async throws -> Data {
        var request = URLRequest(url: Self.userInfoEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard statusCode == 200 else {
            throw GoogleOAuthFlowError.userInfoRequestFailed(
                statusCode: statusCode,
                bodyByteCount: data.count
            )
        }
        return data
    }

    // MARK: - Token response decoding

    nonisolated static func decodeTokenResponse(from data: Data) throws -> GoogleOAuthResult {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
        }
        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GoogleOAuthFlowError.malformedTokenResponse(reason: "JSON decode error")
        }
        guard !response.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleOAuthFlowError.malformedTokenResponse(reason: "missing access_token")
        }
        guard let refreshToken = response.refresh_token,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleOAuthFlowError.malformedTokenResponse(reason: "missing refresh_token")
        }
        throw GoogleOAuthFlowError.malformedTokenResponse(reason: "token-bound UserInfo response required")
    }

    nonisolated static func decodeTokenResponse(
        from data: Data,
        userInfoData: Data,
        now: Date = Date()
    ) throws -> GoogleOAuthResult {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let refresh_token_expires_in: Int?
            let expires_in: Int?
            let id_token: String?
            let scope: String?
        }

        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GoogleOAuthFlowError.malformedTokenResponse(
                reason: "JSON decode error"
            )
        }

        guard !response.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleOAuthFlowError.malformedTokenResponse(reason: "missing access_token")
        }

        guard let refreshToken = response.refresh_token,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw GoogleOAuthFlowError.malformedTokenResponse(
                reason: "missing refresh_token — ensure access_type=offline and prompt=consent"
            )
        }

        let subject = try extractSubject(from: response.id_token)
        let userInfo = try decodeUserInfo(from: userInfoData)
        guard userInfo.sub == subject else {
            throw GoogleOAuthFlowError.identityMismatch
        }
        guard userInfo.emailVerified else {
            throw GoogleOAuthFlowError.malformedUserInfoResponse(reason: "email is not verified")
        }
        guard !userInfo.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleOAuthFlowError.missingEmail
        }

        let expiresAt: Date
        if let expiresIn = response.expires_in {
            expiresAt = now.addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expiresAt = .distantFuture
        }

        let grantedScopes = Set(
            (response.scope ?? "")
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
        )
        let refreshTokenExpiresAt = response.refresh_token_expires_in.map {
            now.addingTimeInterval(TimeInterval($0))
        }

        return GoogleOAuthResult(
            accessToken: response.access_token,
            refreshToken: refreshToken,
            email: userInfo.email,
            expiresAt: expiresAt,
            subject: userInfo.sub,
            hostedDomain: userInfo.hostedDomain,
            grantedScopes: grantedScopes,
            refreshTokenExpiresAt: refreshTokenExpiresAt
        )
    }

    private struct GoogleUserInfo: Decodable {
        let sub: String
        let email: String
        let email_verified: Bool?
        let hd: String?

        var emailVerified: Bool { email_verified == true }
        var hostedDomain: String? {
            guard let hd else { return nil }
            let value = hd.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    private nonisolated static func decodeUserInfo(from data: Data) throws -> GoogleUserInfo {
        do {
            let profile = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
            guard !profile.sub.isEmpty else {
                throw GoogleOAuthFlowError.malformedUserInfoResponse(reason: "missing subject")
            }
            return profile
        } catch let error as GoogleOAuthFlowError {
            throw error
        } catch {
            throw GoogleOAuthFlowError.malformedUserInfoResponse(reason: "JSON decode error")
        }
    }

    /// Extracts only the subject from the Google `id_token`.
    ///
    /// The JWT payload is not treated as an authority for email identity. The
    /// access-token-bound UserInfo response is authoritative; this subject is
    /// compared only to detect a mismatched or forged token response.
    private nonisolated static func extractSubject(from idToken: String?) throws -> String {
        guard let idToken, !idToken.isEmpty else {
            throw GoogleOAuthFlowError.missingEmail
        }

        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw GoogleOAuthFlowError.malformedTokenResponse(reason: "invalid id_token")
        }

        // JWT payload is the second segment, base64url-encoded without padding.
        let payloadB64 = String(parts[1])
        let padded = payloadB64 + String(repeating: "=", count: (4 - payloadB64.count % 4) % 4)
        let normalised = padded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: normalised),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              !subject.isEmpty
        else {
            throw GoogleOAuthFlowError.malformedTokenResponse(reason: "invalid id_token")
        }
        return subject
    }

    // MARK: - Helpers

    private func formEncode(_ items: [String: String]) -> Data {
        OAuthFormEncoding.encode(items)
    }
}

#if os(macOS)
@MainActor
private final class GoogleOAuthWebSessionCompletion {
    private var continuation: CheckedContinuation<URL, Error>?

    init(continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning url: URL) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(returning: url)
        return true
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(throwing: error)
        return true
    }
}
#endif

// MARK: - Presentation provider

@MainActor
private final class AnchorPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
