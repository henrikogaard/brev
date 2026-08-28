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

import Foundation

// MARK: - OAuth2 client credentials

/// OAuth2 client credentials injected by the app bundle or launch environment.
public struct OAuthClientConfiguration: Sendable, Hashable {
    public let googleMacOSClientID: String
    public let googleIOSClientID: String
    public let googleMacOSRedirectURI: String
    public let googleMacOSCallbackScheme: String
    public let googleIOSRedirectURI: String
    public let googleIOSCallbackScheme: String
    public let googleClientSecret: String
    public let microsoftClientID: String

    /// The platform-specific Google client ID selected by this build.
    public var googleClientID: String {
        #if os(iOS)
        googleIOSClientID
        #else
        googleMacOSClientID
        #endif
    }

    /// The platform-specific Google callback configuration selected by this build.
    public var googleOAuthConfiguration: GoogleOAuthPlatformConfiguration {
        #if os(iOS)
        GoogleOAuthPlatformConfiguration(
            clientID: googleIOSClientID,
            redirectURI: googleIOSRedirectURI,
            callbackScheme: googleIOSCallbackScheme,
            platform: .iOS
        )
        #else
        GoogleOAuthPlatformConfiguration(
            clientID: googleMacOSClientID,
            redirectURI: googleMacOSRedirectURI,
            callbackScheme: googleMacOSCallbackScheme,
            platform: .macOS
        )
        #endif
    }

    public var canStartGoogleOAuth: Bool {
        googleOAuthConfiguration.isValid
    }

    public var canStartMicrosoftOAuth: Bool {
        !microsoftClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        googleClientID: String = "",
        googleClientSecret: String = "",
        microsoftClientID: String = "",
        googleMacOSClientID: String? = nil,
        googleIOSClientID: String? = nil,
        googleMacOSRedirectURI: String = "http://127.0.0.1",
        googleMacOSCallbackScheme: String = "http",
        googleIOSRedirectURI: String? = nil,
        googleIOSCallbackScheme: String? = nil
    ) {
        let legacyID = Self.normalise(googleClientID)
        let resolvedIOSID = Self.normalise(googleIOSClientID ?? legacyID)
        let defaultIOSScheme = GoogleOAuthPlatformConfiguration.reversedClientID(resolvedIOSID)
            ?? "eu.brevmail.brev"
        let callbackSchemeOverride = Self.normalise(googleIOSCallbackScheme ?? "")
        let resolvedIOSScheme = callbackSchemeOverride.isEmpty ? defaultIOSScheme : callbackSchemeOverride
        let redirectURIOverride = Self.normalise(googleIOSRedirectURI ?? "")
        self.googleMacOSClientID = Self.normalise(googleMacOSClientID ?? legacyID)
        self.googleIOSClientID = resolvedIOSID
        self.googleMacOSRedirectURI = Self.normalise(googleMacOSRedirectURI)
        self.googleMacOSCallbackScheme = Self.normalise(googleMacOSCallbackScheme)
        self.googleIOSRedirectURI = redirectURIOverride.isEmpty
            ? "\(resolvedIOSScheme):/oauth2redirect"
            : redirectURIOverride
        self.googleIOSCallbackScheme = resolvedIOSScheme
        self.googleClientSecret = googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.microsoftClientID = microsoftClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Process-wide configuration, evaluated once. Reuse this instead of calling
    /// `load()` repeatedly — `load()` bridges the full process environment and
    /// reads `Bundle.main.infoDictionary`, which is wasteful on every view init.
    public static let shared = load()

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> OAuthClientConfiguration {
        let localQAFallback = isTruthy(environment["BREV_LOCAL_QA"])
            || isTruthy(environment["BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK"])
        let legacyID = localQAFallback
            ? resolvedValue(
                environmentKey: "BREV_GOOGLE_OAUTH_CLIENT_ID",
                infoDictionaryKey: "BREVGoogleOAuthClientID",
                environment: environment,
                infoDictionary: infoDictionary
            )
            : ""
        return OAuthClientConfiguration(
            googleClientID: "",
            googleClientSecret: resolvedValue(
                environmentKey: "BREV_GOOGLE_OAUTH_CLIENT_SECRET",
                infoDictionaryKey: "BREVGoogleOAuthClientSecret",
                environment: environment,
                infoDictionary: infoDictionary
            ),
            microsoftClientID: resolvedValue(
                environmentKey: "BREV_MICROSOFT_OAUTH_CLIENT_ID",
                infoDictionaryKey: "BREVMicrosoftOAuthClientID",
                environment: environment,
                infoDictionary: infoDictionary
            ),
            googleMacOSClientID: resolvedPlatformValue(
                environmentKey: "BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID",
                infoDictionaryKey: "BREVGoogleOAuthMacOSClientID",
                environment: environment,
                infoDictionary: infoDictionary,
                fallback: legacyID
            ),
            googleIOSClientID: resolvedPlatformValue(
                environmentKey: "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID",
                infoDictionaryKey: "BREVGoogleOAuthIOSClientID",
                environment: environment,
                infoDictionary: infoDictionary,
                fallback: legacyID
            ),
            googleMacOSRedirectURI: resolvedPlatformValue(
                environmentKey: "BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI",
                infoDictionaryKey: "BREVGoogleOAuthMacOSRedirectURI",
                environment: environment,
                infoDictionary: infoDictionary,
                fallback: "http://127.0.0.1"
            ),
            googleMacOSCallbackScheme: resolvedPlatformValue(
                environmentKey: "BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME",
                infoDictionaryKey: "BREVGoogleOAuthMacOSCallbackScheme",
                environment: environment,
                infoDictionary: infoDictionary,
                fallback: "http"
            ),
            googleIOSRedirectURI: resolvedPlatformValue(
                environmentKey: "BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI",
                infoDictionaryKey: "BREVGoogleOAuthIOSRedirectURI",
                environment: environment,
                infoDictionary: infoDictionary,
                fallback: ""
            ),
            googleIOSCallbackScheme: resolvedPlatformValue(
                environmentKey: "BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME",
                infoDictionaryKey: "BREVGoogleOAuthIOSCallbackScheme",
                environment: environment,
                infoDictionary: infoDictionary,
                fallback: ""
            ),
        )
    }

    private static func resolvedPlatformValue(
        environmentKey: String,
        infoDictionaryKey: String,
        environment: [String: String],
        infoDictionary: [String: Any]?,
        fallback: String
    ) -> String {
        resolvedValue(
            environmentKey: environmentKey,
            infoDictionaryKey: infoDictionaryKey,
            environment: environment,
            infoDictionary: infoDictionary
        ).isEmpty ? fallback : resolvedValue(
            environmentKey: environmentKey,
            infoDictionaryKey: infoDictionaryKey,
            environment: environment,
            infoDictionary: infoDictionary
        )
    }

    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private static func normalise(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedValue(
        environmentKey: String,
        infoDictionaryKey: String,
        environment: [String: String],
        infoDictionary: [String: Any]?
    ) -> String {
        if let environmentValue = nonBlankString(environment[environmentKey]) {
            return environmentValue
        }
        if let infoDictionaryValue = nonBlankString(infoDictionary?[infoDictionaryKey] as? String) {
            return infoDictionaryValue
        }
        return ""
    }

    private static func nonBlankString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private let loadedOAuthClientConfiguration = OAuthClientConfiguration.shared

/// The platform-specific Google OAuth2 client ID for this build.
public let GoogleOAuthClientID = loadedOAuthClientConfiguration.googleClientID

/// The exact platform-specific Google redirect URI for this build.
public let GoogleOAuthRedirectURI = loadedOAuthClientConfiguration.googleOAuthConfiguration.redirectURI

/// The platform-specific callback scheme for this build.
public let GoogleOAuthCallbackScheme = loadedOAuthClientConfiguration.googleOAuthConfiguration.callbackScheme

/// The Google OAuth2 client secret for the Brev app.
///
/// Obtained from the same credentials page as `GoogleOAuthClientID`.
public let GoogleOAuthClientSecret = loadedOAuthClientConfiguration.googleClientSecret

/// The Microsoft (Azure) OAuth2 client ID for the Brev app.
///
/// Register a multi-tenant app at https://portal.azure.com, enable
/// the Mail.ReadWrite and SMTP.Send delegated permissions, and set
/// `brev://oauth` as a redirect URI of type "Mobile and desktop applications."
public let OutlookOAuthClientID = loadedOAuthClientConfiguration.microsoftClientID

// MARK: - Token refresh errors

/// Errors produced by `OAuthTokenRefresher`.
public enum OAuthRefreshError: Error, Sendable, Equatable, LocalizedError {
    /// The server returned a non-200 response. Only the response status and
    /// body byte count are retained; the body can contain token or credential
    /// fragments.
    case refreshFailed(statusCode: Int, bodyByteCount: Int)
    /// Google rejected the refresh credential and the account must sign in
    /// again. The provider's response body is intentionally not retained.
    case reauthenticationRequired
    /// The server returned a 200 but the response body could not be decoded.
    case malformedResponse(reason: String)
    /// The refresh token is missing or empty.
    case missingRefreshToken

    /// Whether retrying later can succeed without user action.
    public var isPermanent: Bool {
        switch self {
        case .reauthenticationRequired, .missingRefreshToken, .malformedResponse:
            return true
        case .refreshFailed(let statusCode, _):
            // 408 and 429 are transient endpoint responses; other 4xx
            // responses represent a rejected client/credential/configuration.
            let isClientError = (400 ..< 500).contains(statusCode)
            return isClientError && statusCode != 408 && statusCode != 429
        }
    }

    public var errorDescription: String? {
        switch self {
        case .refreshFailed(let code, _):
            // The raw body is intentionally omitted: it can contain token or
            // credential fragments (ADR-0006 forbids secrets in error output).
            return String(localized: "OAuth2 token refresh failed (HTTP \(code)).", bundle: .module)
        case .reauthenticationRequired:
            return String(localized: "Your Google sign-in has expired. Sign in again to continue.", bundle: .module)
        case .malformedResponse(let reason):
            return String(localized: "OAuth2 token refresh returned an unreadable response: \(reason)", bundle: .module)
        case .missingRefreshToken:
            return String(localized: "No refresh token is stored for this account.", bundle: .module)
        }
    }
}

// MARK: - Token refresher

/// Exchanges an OAuth2 refresh token for a new access token and
/// persists the result via a `TokenStore`.
///
/// The default endpoint and credentials are set to Google's.
/// Use `OAuthTokenRefresher.outlook(tokenStore:)` for Microsoft accounts.
public struct OAuthTokenRefresher: Sendable {
    private let clientID: String
    /// Optional compatibility secret. Native PKCE clients leave this empty;
    /// when configured, it is held only by this short-lived refresher and is
    /// never persisted or included in an account token record.
    private let clientSecret: String
    private let tokenEndpoint: URL
    private let urlSession: URLSession
    private let tokenStore: any TokenStore
    private let coordinator: OAuthRefreshCoordinator

    /// Creates a refresher for Google OAuth2 tokens.
    ///
    /// - Parameters:
    ///   - clientID: The Google OAuth2 client ID. Defaults to `GoogleOAuthClientID`.
    ///   - clientSecret: The Google OAuth2 client secret. Defaults to `GoogleOAuthClientSecret`.
    ///   - tokenEndpoint: The token endpoint URL. Defaults to Google's.
    ///   - urlSession: The URLSession to use for network requests.
    ///   - tokenStore: The store to persist the refreshed token into.
    ///   - coordinator: Shared per-connector coordinator for concurrent refreshes.
    public init(
        clientID: String = GoogleOAuthClientID,
        clientSecret: String = GoogleOAuthClientSecret,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
        urlSession: URLSession = .shared,
        tokenStore: any TokenStore,
        coordinator: OAuthRefreshCoordinator = OAuthRefreshCoordinator()
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.tokenEndpoint = tokenEndpoint
        self.urlSession = urlSession
        self.tokenStore = tokenStore
        self.coordinator = coordinator
    }

    /// Creates a token refresher for Microsoft (Outlook / Microsoft 365) accounts.
    ///
    /// Microsoft public clients do not require a `client_secret`; an empty
    /// string is passed so the refresh request conforms to the token endpoint's
    /// `application/x-www-form-urlencoded` format without causing errors.
    public static func outlook(
        tokenStore: any TokenStore,
        urlSession: URLSession = .shared,
        coordinator: OAuthRefreshCoordinator = OAuthRefreshCoordinator()
    ) -> OAuthTokenRefresher {
        OAuthTokenRefresher(
            clientID: OutlookOAuthClientID,
            clientSecret: "",
            tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            urlSession: urlSession,
            tokenStore: tokenStore,
            coordinator: coordinator
        )
    }

    /// Refreshes the access token for the given account.
    ///
    /// Reads the stored token's refresh token, calls the Google token endpoint,
    /// and writes the new access token back to the store.
    ///
    /// - Parameter accountID: The Brev account ID whose token should be refreshed.
    /// - Returns: A `Token` with the new access token and expiry.
    /// - Throws: `OAuthRefreshError` on network, server, or decode failure;
    ///   storage errors from `TokenStore` are rethrown unchanged.
    @discardableResult
    public func refresh(for accountID: String) async throws -> Token {
        try await coordinator.run(for: accountID) { [self] in
            try await refreshStoredToken(for: accountID)
        }
    }

    private func refreshStoredToken(for accountID: String) async throws -> Token {
        guard let existing = await tokenStore.token(for: accountID) else {
            throw OAuthRefreshError.missingRefreshToken
        }
        let refreshToken = existing.refreshToken
        guard !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OAuthRefreshError.missingRefreshToken
        }

        let newToken = try await fetchFreshToken(
            refreshToken: refreshToken,
            oauthMetadata: existing.oauthMetadata,
            refreshTokenExpiresAt: existing.refreshTokenExpiresAt
        )
        try await tokenStore.setToken(newToken, for: accountID)
        return newToken
    }

    /// Exchanges a raw refresh token for a new access token without looking up
    /// an account. Useful during initial provisioning before an account ID is
    /// known.
    ///
    /// - Parameters:
    ///   - refreshToken: The OAuth2 refresh token to exchange.
    ///   - accountID: If non-nil, the result is persisted to the token store.
    /// - Returns: A `Token` with the new access token and expiry.
    /// - Throws: `OAuthRefreshError` on network, server, or decode failure;
    ///   storage errors from `TokenStore` are rethrown unchanged.
    public func refresh(
        refreshToken: String,
        storeTo accountID: String? = nil
    ) async throws -> Token {
        guard !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OAuthRefreshError.missingRefreshToken
        }
        if let accountID {
            return try await coordinator.run(for: accountID) { [self] in
                let existingToken = await tokenStore.token(for: accountID)
                let token = try await fetchFreshToken(
                    refreshToken: refreshToken,
                    oauthMetadata: existingToken?.oauthMetadata,
                    refreshTokenExpiresAt: existingToken?.refreshTokenExpiresAt
                )
                return try await persist(token, for: accountID)
            }
        }
        return try await fetchFreshToken(refreshToken: refreshToken)
    }

    private func persist(_ token: Token, for accountID: String) async throws -> Token {
        try await tokenStore.setToken(token, for: accountID)
        return token
    }

    // MARK: - Private

    private func fetchFreshToken(
        refreshToken: String,
        oauthMetadata: OAuthTokenMetadata? = nil,
        refreshTokenExpiresAt: Date? = nil
    ) async throws -> Token {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ]
        // Native/public Google clients authenticate with PKCE and have no
        // confidential secret. Omit the field instead of sending an empty
        // client_secret, which keeps the request aligned with Google's
        // installed-app token contract.
        if !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["client_secret"] = clientSecret
        }
        request.httpBody = formEncode(body)

        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard statusCode == 200 else {
            if Self.isReauthenticationError(data) {
                throw OAuthRefreshError.reauthenticationRequired
            }
            throw OAuthRefreshError.refreshFailed(
                statusCode: statusCode,
                bodyByteCount: data.count
            )
        }

        return try decodeToken(
            from: data,
            fallbackRefreshToken: refreshToken,
            oauthMetadata: oauthMetadata,
            refreshTokenExpiresAt: refreshTokenExpiresAt
        )
    }

    private static func isReauthenticationError(_ data: Data) -> Bool {
        struct OAuthErrorResponse: Decodable { let error: String? }
        guard let response = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data),
              let code = response.error?.lowercased()
        else { return false }
        return ["invalid_grant", "invalid_client", "unauthorized_client"].contains(code)
    }

    private func decodeToken(
        from data: Data,
        fallbackRefreshToken: String,
        oauthMetadata: OAuthTokenMetadata? = nil,
        refreshTokenExpiresAt: Date? = nil
    ) throws -> Token {
        struct RefreshResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let refresh_token_expires_in: Int?
            let expires_in: Int?
        }

        let decoded: RefreshResponse
        do {
            decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
        } catch {
            throw OAuthRefreshError.malformedResponse(
                reason: "could not decode JSON"
            )
        }

        guard !decoded.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OAuthRefreshError.malformedResponse(reason: "missing access_token field")
        }

        // Google typically omits refresh_token in refresh responses; preserve the original.
        let effectiveRefreshToken = decoded.refresh_token
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? fallbackRefreshToken

        let expiresAt: Date
        if let expiresIn = decoded.expires_in {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expiresAt = .distantFuture
        }

        return Token(
            accessToken: decoded.access_token,
            refreshToken: effectiveRefreshToken,
            expiresAt: expiresAt,
            refreshTokenExpiresAt: decoded.refresh_token_expires_in.map {
                Date().addingTimeInterval(TimeInterval($0))
            } ?? refreshTokenExpiresAt,
            oauthMetadata: oauthMetadata
        )
    }

    private func formEncode(_ items: [String: String]) -> Data {
        OAuthFormEncoding.encode(items)
    }
}
