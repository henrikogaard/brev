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

// MARK: - Outlook OAuth2 flow errors

/// Errors produced by `OutlookOAuthFlow`.
public enum OutlookOAuthFlowError: Error, Sendable, Equatable, LocalizedError {
    case missingClientID
    case userCancelled
    case missingCodeInCallback
    case authorizationFailed(error: String, description: String?)
    case stateMismatch
    /// The token exchange HTTP call returned a non-200 status. Only the
    /// response status and body byte count are retained; the body can contain
    /// token or credential fragments.
    case tokenExchangeFailed(statusCode: Int, bodyByteCount: Int)
    case malformedTokenResponse(reason: String)
    case missingEmail
    case presentationContextUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return String(localized: "Microsoft sign-in is not configured in this build.", bundle: .module)
        case .userCancelled:
            return String(localized: "Microsoft sign-in was cancelled.", bundle: .module)
        case .missingCodeInCallback:
            return String(localized: "Microsoft did not return an authorization code.", bundle: .module)
        case .authorizationFailed(let error, let description):
            let detail = description.map { ": \($0)" } ?? ""
            return String(localized: "Microsoft rejected sign-in (\(error))\(detail)", bundle: .module)
        case .stateMismatch:
            return String(localized: "Microsoft sign-in returned an unexpected security state.", bundle: .module)
        case .tokenExchangeFailed(let code, _):
            // The raw body is intentionally omitted: it can contain token or
            // credential fragments (ADR-0006 forbids secrets in error output).
            return String(localized: "Microsoft rejected the token exchange (HTTP \(code)).", bundle: .module)
        case .malformedTokenResponse(let reason):
            return String(localized: "Microsoft returned an unreadable token response: \(reason)", bundle: .module)
        case .missingEmail:
            return String(localized: "Microsoft did not return the user's email address in the token.", bundle: .module)
        case .presentationContextUnavailable:
            return String(localized: "Brev could not open the Microsoft sign-in sheet.", bundle: .module)
        }
    }
}

// MARK: - OAuth result

/// The result of a completed Microsoft OAuth2 authorization flow.
public struct OutlookOAuthResult: Sendable, Hashable {
    public let accessToken: String
    public let refreshToken: String
    public let email: String
    public let expiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        email: String,
        expiresAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email
        self.expiresAt = expiresAt
    }

    public func asToken() -> Token {
        Token(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}

// MARK: - Outlook OAuth2 flow

/// Drives the interactive Microsoft (Outlook/Microsoft 365) sign-in flow
/// using `ASWebAuthenticationSession`.
///
/// Cross-platform (macOS + iOS). The flow:
/// 1. Build the Microsoft identity authorization URL with IMAP/SMTP scopes.
/// 2. Open `ASWebAuthenticationSession` anchored on the caller-supplied window.
/// 3. Exchange the returned `code` for access + refresh tokens.
/// 4. Decode the `preferred_username` claim from the id_token to obtain the email.
///
/// The callback scheme is `brev://oauth`. This must be registered as a
/// custom URL scheme in both app targets' `Info.plist`.
@MainActor
public final class OutlookOAuthFlow {
    /// Microsoft identity authorization endpoint (multi-tenant).
    public static let authorizationEndpoint = URL(
        string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    )!
    /// Microsoft identity token endpoint (multi-tenant).
    public static let tokenEndpoint = URL(
        string: "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    )!
    /// The redirect URI registered for Brev's custom scheme.
    public static let redirectURI = "brev://oauth"
    /// The callback scheme. Must match `redirectURI`.
    public static let callbackScheme = "brev"
    /// IMAP + SMTP delegated scopes required for XOAUTH2.
    public static let scopes = [
        "https://outlook.office.com/IMAP.AccessAsUser.All",
        "https://outlook.office.com/SMTP.Send",
        "offline_access",
        "openid",
        "email",
        "profile",
    ]

    private let clientID: String
    private let urlSession: URLSession
    private var pendingSession: ASWebAuthenticationSession?
    private var pendingPresentationProvider: OutlookAnchorPresentationProvider?

    public init(
        clientID: String = OutlookOAuthClientID,
        urlSession: URLSession = .shared
    ) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
    }

    // MARK: - Public interface

    /// Run the interactive Microsoft sign-in flow from start to finish.
    ///
    /// Presents a system web sheet anchored on `presentationContext`, completes
    /// the code exchange, and returns the resulting tokens and email address.
    ///
    /// - Parameter presentationContext: The window to anchor the web sheet on.
    /// - Returns: An `OutlookOAuthResult` containing the access token, refresh
    ///   token, email, and expiry.
    /// - Throws: `OutlookOAuthFlowError` on cancellation, server rejection, or
    ///   decode failure.
    public func signIn(
        presentationContext: ASPresentationAnchor
    ) async throws -> OutlookOAuthResult {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OutlookOAuthFlowError.missingClientID
        }
        let state = UUID().uuidString
        // Generate the PKCE pair at auth-URL-build time and carry the verifier
        // through to the token exchange for this same flow instance (RFC 7636).
        let pkce = PKCECodePair()
        let authURL = buildAuthorizationURL(state: state, pkce: pkce)

        let callbackURL = try await runWebAuthSession(
            authorizationURL: authURL,
            presentationContext: presentationContext
        )

        let code = try Self.extractAuthorizationCode(from: callbackURL, expectedState: state)
        return try await exchangeCodeForTokens(code: code, codeVerifier: pkce.verifier)
    }

    // MARK: - Authorization URL

    func buildAuthorizationURL(state: String, pkce: PKCECodePair = PKCECodePair()) -> URL {
        var components = URLComponents(
            url: Self.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            // PKCE: bind the authorization code to this client (RFC 7636).
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "response_mode", value: "query"),
        ]
        return components.url!
    }

    // MARK: - ASWebAuthenticationSession

    private func runWebAuthSession(
        authorizationURL: URL,
        presentationContext: ASPresentationAnchor
    ) async throws -> URL {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: Self.callbackScheme
                ) { [weak self] callbackURL, error in
                    self?.pendingSession = nil
                    self?.pendingPresentationProvider = nil
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionErrorDomain
                            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            continuation.resume(throwing: OutlookOAuthFlowError.userCancelled)
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: OutlookOAuthFlowError.missingCodeInCallback)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
                let provider = OutlookAnchorPresentationProvider(anchor: presentationContext)
                session.presentationContextProvider = provider
                session.prefersEphemeralWebBrowserSession = true
                pendingSession = session
                pendingPresentationProvider = provider
                if !session.start() {
                    pendingSession = nil
                    pendingPresentationProvider = nil
                    continuation.resume(
                        throwing: OutlookOAuthFlowError.presentationContextUnavailable
                    )
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.pendingSession?.cancel()
                self?.pendingSession = nil
                self?.pendingPresentationProvider = nil
            }
        }
    }

    // MARK: - Code extraction

    nonisolated static func extractAuthorizationCode(
        from url: URL,
        expectedState: String
    ) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OutlookOAuthFlowError.missingCodeInCallback
        }
        let items = components.queryItems ?? []

        let receivedState = items.first(where: { $0.name == "state" })?.value
        guard receivedState == expectedState else {
            throw OutlookOAuthFlowError.stateMismatch
        }

        if let error = items.first(where: { $0.name == "error" })?.value,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OutlookOAuthFlowError.authorizationFailed(
                error: error,
                description: items.first(where: { $0.name == "error_description" })?.value
            )
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OutlookOAuthFlowError.missingCodeInCallback
        }
        return code
    }

    // MARK: - Token exchange

    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String
    ) async throws -> OutlookOAuthResult {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        // Outlook is a public client: PKCE replaces the client secret, so no
        // client_secret is sent. The code_verifier proves possession of the
        // verifier matching the sent code_challenge (RFC 7636).
        request.httpBody = formEncode([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "redirect_uri": Self.redirectURI,
            "scope": Self.scopes.joined(separator: " "),
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard statusCode == 200 else {
            throw OutlookOAuthFlowError.tokenExchangeFailed(
                statusCode: statusCode,
                bodyByteCount: data.count
            )
        }

        return try Self.decodeTokenResponse(from: data)
    }

    // MARK: - Token response decoding

    nonisolated static func decodeTokenResponse(from data: Data) throws -> OutlookOAuthResult {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let id_token: String?
        }

        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw OutlookOAuthFlowError.malformedTokenResponse(
                reason: "JSON decode error"
            )
        }

        guard !response.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OutlookOAuthFlowError.malformedTokenResponse(reason: "missing access_token")
        }

        guard let refreshToken = response.refresh_token,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OutlookOAuthFlowError.malformedTokenResponse(
                reason: "missing refresh_token — ensure offline_access scope is requested"
            )
        }

        let email = try extractEmail(from: response.id_token)

        let expiresAt: Date
        if let expiresIn = response.expires_in {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expiresAt = .distantFuture
        }

        return OutlookOAuthResult(
            accessToken: response.access_token,
            refreshToken: refreshToken,
            email: email,
            expiresAt: expiresAt
        )
    }

    /// Extracts the email from the Microsoft `id_token` (JWT) via the
    /// `preferred_username` or `email` claim.
    private nonisolated static func extractEmail(from idToken: String?) throws -> String {
        guard let idToken, !idToken.isEmpty else {
            throw OutlookOAuthFlowError.missingEmail
        }

        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            throw OutlookOAuthFlowError.missingEmail
        }

        let payloadB64 = String(parts[1])
        let padded = payloadB64 + String(repeating: "=", count: (4 - payloadB64.count % 4) % 4)
        let normalised = padded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard
            let data = Data(base64Encoded: normalised),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw OutlookOAuthFlowError.missingEmail
        }

        // Microsoft uses `preferred_username` for the UPN, which is the email address
        // for personal and commercial accounts.
        if let email = json["preferred_username"] as? String, !email.isEmpty {
            return email
        }
        if let email = json["email"] as? String, !email.isEmpty {
            return email
        }
        throw OutlookOAuthFlowError.missingEmail
    }

    // MARK: - Helpers

    private func formEncode(_ items: [String: String]) -> Data {
        OAuthFormEncoding.encode(items)
    }
}

// MARK: - Presentation provider

@MainActor
private final class OutlookAnchorPresentationProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
