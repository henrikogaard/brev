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

/// Persistent identity store for the set of accounts a user has
/// added to Brev. The `MailBackend` adapter (one per provider) is
/// responsible for keeping the store in sync with its own internal
/// account-management state — this protocol is the only surface
/// the view layer reads (per ADR-0066).
public protocol AccountStore: Sendable {
    /// Snapshot of every account currently signed in.
    var accounts: [BrevAccount] { get async }
    /// The account currently driving the inbox UI, if any.
    var current: BrevAccount? { get async }
    /// Set the active account by id. No-op if id is unknown.
    func setCurrent(_ id: String) async
    /// Register a freshly signed-in account.
    func add(_ account: BrevAccount) async
    /// Remove an account and any associated tokens.
    func remove(_ id: String) async
    /// Observe changes to the account list.
    func subscribe() -> AsyncStream<[BrevAccount]>
}

/// Persistent token store keyed by account id. Implementations
/// should write to a platform-secure backing (Keychain on Apple
/// platforms); see `KeychainTokenStore`.
public protocol TokenStore: Sendable {
    func token(for accountID: String) async -> Token?
    /// Persists a token, surfacing Keychain/storage failures to the caller.
    func setToken(_ token: Token, for accountID: String) async throws
    func clearToken(for accountID: String) async
    /// Clears a token while surfacing secure-store failures to lifecycle callers.
    ///
    /// The default implementation preserves compatibility for existing token
    /// stores whose historical clear operation cannot report an error.
    func clearTokenChecked(for accountID: String) async throws
}

public extension TokenStore {
    /// Compatibility implementation for token stores with a non-throwing clear.
    func clearTokenChecked(for accountID: String) async throws {
        await clearToken(for: accountID)
    }

    /// Store a freshly-issued token for an operation that immediately
    /// needs authenticated backend access, restoring the previous token
    /// state if that operation fails before the session is fully
    /// installed.
    func withTokenInstalled<Result>(
        _ token: Token,
        for accountID: String,
        perform operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        let previousToken = await self.token(for: accountID)
        try await setToken(token, for: accountID)
        do {
            return try await operation()
        } catch {
            if let previousToken {
                try? await setToken(previousToken, for: accountID)
            } else {
                await clearToken(for: accountID)
            }
            throw error
        }
    }
}

/// Non-secret metadata associated with an OAuth token.
///
/// The token values themselves remain Keychain-backed. This metadata lets a
/// provider restore the account identity and capability gates without using an
/// email address as a durable key.
public struct OAuthTokenMetadata: Sendable, Hashable, Codable {
    /// Provider mode that issued the token.
    public let providerMode: GoogleOAuthProviderMode
    /// Stable Google OIDC subject, when the token belongs to Google OAuth.
    public let googleSubject: String?
    /// Verified Workspace hosted domain, when Google supplied one.
    public let hostedDomain: String?
    /// OAuth scopes actually granted by the authorization server.
    public let grantedScopes: Set<String>

    /// Creates non-secret OAuth metadata for a persisted token.
    public init(
        providerMode: GoogleOAuthProviderMode,
        googleSubject: String? = nil,
        hostedDomain: String? = nil,
        grantedScopes: Set<String> = []
    ) {
        self.providerMode = providerMode
        self.googleSubject = googleSubject?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostedDomain = hostedDomain?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.grantedScopes = Set(
            grantedScopes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

/// OAuth bearer token bundle. Refresh handling lives in the
/// backend adapter that issued the token.
public struct Token: Sendable, Hashable, Codable {
    public let accessToken: String
    public let refreshToken: String
    /// When the refresh token expires, when the provider supplies that value.
    public let refreshTokenExpiresAt: Date?
    public let expiresAt: Date
    /// Optional provider metadata. Missing metadata is valid for legacy tokens.
    public let oauthMetadata: OAuthTokenMetadata?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        refreshTokenExpiresAt: Date? = nil,
        oauthMetadata: OAuthTokenMetadata? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.expiresAt = expiresAt
        self.oauthMetadata = oauthMetadata
    }

    /// True when the access token is within 60 seconds of expiry.
    public var isExpired: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }
}
