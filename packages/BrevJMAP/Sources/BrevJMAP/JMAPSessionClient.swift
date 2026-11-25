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
import Foundation

/// Supplies a current Bearer token for authenticating JMAP HTTPS requests.
public protocol JMAPAccessTokenProvider: Sendable {
    /// Returns a non-empty Bearer token or throws `JMAPError.missingToken` / `.authenticationRequired`.
    func bearerToken() async throws -> String
}

/// Static bearer token provider for tests and one-shot setup validation.
public struct StaticJMAPAccessTokenProvider: JMAPAccessTokenProvider {
    private let token: String

    /// Creates a provider backed by an in-memory token.
    public init(token: String) {
        self.token = token
    }

    /// Returns the trimmed token or throws `.missingToken` if blank.
    public func bearerToken() async throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JMAPError.missingToken
        }
        return trimmed
    }
}

/// Reads the JMAP account's Bearer / API token strictly from `TokenStore` (Keychain).
public struct JMAPTokenStoreAccessTokenProvider: JMAPAccessTokenProvider {
    private let accountID: String
    private let tokenStore: any TokenStore

    /// Creates a Keychain-backed token provider for `accountID`.
    public init(accountID: String, tokenStore: any TokenStore) {
        self.accountID = accountID
        self.tokenStore = tokenStore
    }

    /// Reads the stored Bearer token without logging or caching it on disk.
    public func bearerToken() async throws -> String {
        guard let token = await tokenStore.token(for: accountID) else {
            throw JMAPError.missingToken
        }
        let trimmed = token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JMAPError.missingToken
        }
        return trimmed
    }
}

/// Discovers and validates an RFC 8620 §2 JMAP Session resource over strict HTTPS.
public struct JMAPSessionClient: Sendable {
    private let transport: any JMAPHTTPTransport

    /// Creates a session discovery client with an injectable HTTP transport.
    public init(transport: any JMAPHTTPTransport = URLSessionJMAPHTTPTransport.shared) {
        self.transport = transport
    }

    /// Fetches and validates the JMAP Session resource from an explicit session URL or `/.well-known/jmap` host.
    ///
    /// - Parameters:
    ///   - sessionURLString: Explicit HTTPS session URL or bare domain/host.
    ///   - bearerToken: API token or OAuth 2.0 Bearer token sent via `Authorization: Bearer`.
    /// - Returns: Validated `JMAPSession` with strict HTTPS endpoints.
    public func discoverSession(
        from sessionURLString: String,
        bearerToken: String
    ) async throws -> JMAPSession {
        let discoveryURL = try JMAPURLValidator.discoveryURL(from: sessionURLString)
        return try await discoverSession(from: discoveryURL, bearerToken: bearerToken)
    }

    /// Fetches and validates the JMAP Session resource from a pre-validated HTTPS URL.
    public func discoverSession(
        from sessionURL: URL,
        bearerToken: String
    ) async throws -> JMAPSession {
        let validatedURL = try JMAPURLValidator.validateHTTPSURL(sessionURL)
        let trimmedToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw JMAPError.authenticationRequired
        }

        let request = JMAPHTTPRequest(
            url: validatedURL,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(trimmedToken)",
                "Accept": "application/json"
            ]
        )
        let response = try await transport.send(request)
        try Self.validateHTTPStatus(response)

        let session: JMAPSession
        do {
            session = try JSONDecoder().decode(JMAPSession.self, from: response.body)
        } catch {
            throw JMAPError.invalidResponse
        }

        // Enforce strict HTTPS on every server-advertised endpoint template.
        _ = try JMAPURLValidator.validateHTTPSURL(session.apiUrl)
        try Self.validateTemplateUsesHTTPS(session.downloadUrl, invalidError: .invalidDownloadURL)
        try Self.validateTemplateUsesHTTPS(session.uploadUrl, invalidError: .invalidUploadURL)
        if let eventSourceUrl = session.eventSourceUrl, !eventSourceUrl.isEmpty {
            try Self.validateTemplateUsesHTTPS(eventSourceUrl, invalidError: .invalidResponse)
        }

        guard session.primaryMailAccountID != nil else {
            throw JMAPError.missingPrimaryMailAccount
        }
        return session
    }

    static func validateHTTPStatus(_ response: JMAPHTTPResponse) throws {
        switch response.statusCode {
        case 200 ... 299:
            return
        case 401:
            throw JMAPError.authenticationRequired
        case 403:
            throw JMAPError.forbidden
        case 429:
            throw JMAPError.rateLimited(retryAfter: response.retryAfterSeconds)
        case 500 ... 599:
            throw JMAPError.serverError(statusCode: response.statusCode)
        default:
            throw JMAPError.httpError(statusCode: response.statusCode)
        }
    }

    private static func validateTemplateUsesHTTPS(_ template: String, invalidError: JMAPError) throws {
        let probe = template.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        guard let url = URL(string: probe) else {
            throw invalidError
        }
        do {
            _ = try JMAPURLValidator.validateHTTPSURL(url)
        } catch {
            throw invalidError
        }
    }
}
