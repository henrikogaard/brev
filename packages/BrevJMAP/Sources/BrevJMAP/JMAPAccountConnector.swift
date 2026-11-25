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

/// A connected native JMAP account paired with its `MailBackend` adapter.
public struct JMAPConnectedAccount: Sendable {
    /// Provider-neutral account metadata consumed by `AppSession`.
    public let account: BrevAccount
    /// Connected native RFC 8620 / RFC 8621 JMAP backend.
    public let backend: JMAPBackend

    /// Creates a connected JMAP account pair.
    public init(account: BrevAccount, backend: JMAPBackend) {
        self.account = account
        self.backend = backend
    }
}

/// Provisions, restores, and removes native JMAP accounts while keeping bearer/API tokens strictly in Keychain.
public struct JMAPAccountConnector: Sendable {
    private let configurationStore: any JMAPAccountConfigurationStore
    private let tokenStore: any TokenStore
    private let transport: any JMAPHTTPTransport

    /// Creates a JMAP account connector with injected configuration, Keychain, and transport seams.
    public init(
        configurationStore: any JMAPAccountConfigurationStore,
        tokenStore: any TokenStore,
        transport: any JMAPHTTPTransport = URLSessionJMAPHTTPTransport.shared
    ) {
        self.configurationStore = configurationStore
        self.tokenStore = tokenStore
        self.transport = transport
    }

    /// Creates the production connector backed by `UserDefaultsJMAPAccountConfigurationStore`,
    /// `KeychainTokenStore`, and `URLSessionJMAPHTTPTransport.shared`.
    public static func standard(
        configurationStore: any JMAPAccountConfigurationStore = UserDefaultsJMAPAccountConfigurationStore(),
        tokenStore: any TokenStore = KeychainTokenStore(),
        transport: any JMAPHTTPTransport = URLSessionJMAPHTTPTransport.shared
    ) -> JMAPAccountConnector {
        JMAPAccountConnector(
            configurationStore: configurationStore,
            tokenStore: tokenStore,
            transport: transport
        )
    }

    /// Validates, connects, and persists a new or updated JMAP account.
    ///
    /// Rolls back Keychain token and configuration changes if session discovery or initial
    /// connection fails.
    public func provision(_ request: JMAPAccountSetupRequest) async throws -> JMAPConnectedAccount {
        let email = request.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.contains("@") else {
            throw JMAPError.invalidConfiguration
        }
        let bearerToken = request.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bearerToken.isEmpty else {
            throw JMAPError.authenticationRequired
        }
        let discoveryURL = try JMAPURLValidator.discoveryURL(from: request.sessionURLString)
        let trimmedDisplayName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedDisplayName.isEmpty ? email : trimmedDisplayName
        let accountID = BrevAccount.jmapAccountID(forEmailAddress: email)

        let previousConfiguration = await configurationStore.configuration(for: accountID)
        // Allocate a fresh credential slot per provisioned session so an already-connected
        // backend bound to a prior origin can never read the replacement token.
        let credentialID = "\(accountID)::\(UUID().uuidString)"
        let newToken = Token(
            accessToken: bearerToken,
            refreshToken: "",
            expiresAt: .distantFuture
        )
        let account = BrevAccount(
            id: accountID,
            displayName: displayName,
            emailAddress: email,
            backendIdentifier: BrevAccount.jmapBackendIdentifier,
            backendDisplayName: BrevAccount.jmapBackendDisplayName
        )

        do {
            try await tokenStore.setToken(newToken, for: credentialID)
            let tokenProvider = JMAPTokenStoreAccessTokenProvider(
                credentialID: credentialID,
                tokenStore: tokenStore
            )
            let backend = JMAPBackend(
                account: account,
                sessionURL: discoveryURL,
                tokenProvider: tokenProvider,
                transport: transport
            )
            try await backend.connect()

            let session = backend.currentSession
            let persistedConfiguration = JMAPAccountConfiguration(
                accountID: accountID,
                emailAddress: email,
                displayName: displayName,
                sessionURL: discoveryURL,
                credentialID: credentialID,
                jmapAccountID: session?.primaryMailAccountID,
                username: session?.username
            )
            try await configurationStore.setConfiguration(persistedConfiguration)
            if let previousCredentialID = previousConfiguration?.credentialID,
               previousCredentialID != credentialID {
                await tokenStore.clearToken(for: previousCredentialID)
            }
            if previousConfiguration?.credentialID != accountID {
                await tokenStore.clearToken(for: accountID)
            }
            return JMAPConnectedAccount(account: account, backend: backend)
        } catch {
            await tokenStore.clearToken(for: credentialID)
            throw error
        }
    }

    /// Restores a previously configured JMAP account from non-secret metadata and its Keychain token.
    public func restore(_ account: BrevAccount) async throws -> JMAPConnectedAccount? {
        guard account.backendIdentifier == BrevAccount.jmapBackendIdentifier else {
            return nil
        }
        guard let configuration = await configurationStore.configuration(for: account.id),
              configuration.accountID == account.id
        else {
            throw JMAPError.invalidConfiguration
        }
        guard await tokenStore.token(for: configuration.credentialID) != nil else {
            throw MailBackendError.authenticationRequired
        }
        let tokenProvider = JMAPTokenStoreAccessTokenProvider(
            credentialID: configuration.credentialID,
            tokenStore: tokenStore
        )
        let backend = JMAPBackend(
            account: account,
            sessionURL: configuration.sessionURL,
            tokenProvider: tokenProvider,
            transport: transport
        )
        try await backend.connect()
        return JMAPConnectedAccount(account: account, backend: backend)
    }

    /// Removes the JMAP account's Keychain bearer token and non-secret metadata.
    public func remove(accountID: String) async throws {
        let configuration = await configurationStore.configuration(for: accountID)
        if let credentialID = configuration?.credentialID, credentialID != accountID {
            try await tokenStore.clearTokenChecked(for: credentialID)
        }
        try await tokenStore.clearTokenChecked(for: accountID)
        await configurationStore.clearConfiguration(for: accountID)
    }
}
