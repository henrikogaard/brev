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

/// A connected Gmail API account and its provider-neutral backend adapter.
public struct GmailConnectedAccount: Sendable {
    /// Stable account metadata consumed by `AppSession`.
    public let account: BrevAccount
    /// Connected native Gmail backend.
    public let backend: GmailAPIBackend

    /// Creates a connected account result.
    public init(account: BrevAccount, backend: GmailAPIBackend) {
        self.account = account
        self.backend = backend
    }
}

/// Errors raised while provisioning or restoring a native Gmail account.
public enum GmailAccountConnectorError: Error, Sendable, Equatable, LocalizedError {
    /// Google did not provide a stable OIDC subject.
    case missingGoogleSubject
    /// Google did not provide a verified email address.
    case missingEmail
    /// The stored account is not a Gmail API account.
    case unsupportedAccount
    /// No access token exists for the account.
    case missingToken
    /// The persisted metadata does not match the requested account.
    case configurationMismatch
    /// Local Gmail records could not be removed; account metadata is retained
    /// so the operation can be retried without losing the account.
    case removalCleanupFailed
    /// Pending Gmail mutations could not be removed after canonical cleanup.
    case pendingCleanupFailed
    /// Token or metadata restoration failed after provisioning could not connect.
    case provisioningRollbackFailed

    /// Safe user-facing description.
    public var errorDescription: String? {
        switch self {
        case .missingGoogleSubject: return String(localized: "Google did not provide a stable account identity.", bundle: .module)
        case .missingEmail: return String(localized: "Google did not provide a verified email address.", bundle: .module)
        case .unsupportedAccount: return String(
                localized: "This account is not configured for Gmail API access.",
                bundle: .module
            )
        case .missingToken: return String(localized: "Gmail authorization is unavailable.", bundle: .module)
        case .configurationMismatch: return String(
                localized: "Saved Gmail account metadata does not match this account.",
                bundle: .module
            )
        case .removalCleanupFailed: return String(
                localized: "Brev could not remove the Gmail account's local data. Try removing it again.",
                bundle: .module
            )
        case .pendingCleanupFailed: return String(
                localized: "Brev removed Gmail mail data but could not clear pending changes. Try removing the account again.",
                bundle: .module
            )
        case .provisioningRollbackFailed: return String(
                localized: "Brev could not restore the previous Gmail sign-in state. Try connecting the account again.",
                bundle: .module
            )
        }
    }
}

/// Supplies an access token for one Gmail account, refreshing through the
/// shared OAuth single-flight coordinator when the cached token is expired.
public struct GmailOAuthAccessTokenProvider: GmailAccessTokenProvider, Sendable {
    private let accountID: String
    private let tokenStore: any TokenStore
    private let refresher: OAuthTokenRefresher

    /// Creates a token provider for one stable Gmail API account.
    public init(
        accountID: String,
        tokenStore: any TokenStore,
        refresher: OAuthTokenRefresher
    ) {
        self.accountID = accountID
        self.tokenStore = tokenStore
        self.refresher = refresher
    }

    /// Returns the current bearer token, refreshing and persisting it as needed.
    public func accessToken() async throws -> String {
        guard let token = await tokenStore.token(for: accountID) else {
            throw GmailAccountConnectorError.missingToken
        }
        if !token.isExpired, !token.accessToken.isEmpty {
            return token.accessToken
        }
        let refreshed: Token
        do {
            refreshed = try await refresher.refresh(for: accountID)
        } catch let error as OAuthRefreshError {
            switch error {
            case .reauthenticationRequired, .missingRefreshToken:
                throw GmailAPIError.reauthenticationRequired
            case .refreshFailed(let statusCode, _)
                where statusCode == 408 || statusCode == 429 || (500 ... 599).contains(statusCode):
                throw GmailAPIError.retryable(statusCode: statusCode, retryAfter: nil)
            case .refreshFailed(let statusCode, _)
                where (400 ..< 500).contains(statusCode):
                throw GmailAPIError.reauthenticationRequired
            case .malformedResponse:
                throw GmailAPIError.reauthenticationRequired
            default:
                throw GmailAPIError.transportFailure
            }
        } catch {
            throw GmailAPIError.transportFailure
        }
        guard !refreshed.accessToken.isEmpty else {
            throw GmailAccountConnectorError.missingToken
        }
        return refreshed.accessToken
    }
}

/// Provisions, restores, and removes Gmail API accounts without exposing
/// provider-specific state to the app's views.
public struct GmailAccountConnector: Sendable {
    /// Creates the canonical store for an account.
    public typealias StoreFactory = @Sendable (String) throws -> any GmailAccountStore
    /// Creates the transport for an account and its token provider.
    public typealias TransportFactory =
        @Sendable (String, any GmailAccessTokenProvider) -> any GmailAPITransporting
    /// Creates the typed Gmail client used by sync and native mutations.
    public typealias ClientFactory =
        @Sendable (String, any GmailAPITransporting) -> (any GmailAPIClientProtocol)?
    /// Creates account-scoped offline mutation storage.
    public typealias MutationQueueFactory =
        @Sendable (String) -> (queue: any OfflineMutationQueue, conflicts: any OfflineMutationConflictStore)

    private let configurationStore: any GmailAccountConfigurationStore
    private let tokenStore: any TokenStore
    private let storeFactory: StoreFactory
    private let transportFactory: TransportFactory
    private let clientFactory: ClientFactory
    private let mutationQueueFactory: MutationQueueFactory?
    private let refresher: OAuthTokenRefresher
    private let platform: GoogleOAuthPlatform

    /// Creates a connector with injected storage, refresh, and transport seams.
    public init(
        configurationStore: any GmailAccountConfigurationStore,
        tokenStore: any TokenStore,
        storeFactory: @escaping StoreFactory,
        transportFactory: @escaping TransportFactory,
        clientFactory: @escaping ClientFactory = { _, _ in nil },
        mutationQueueFactory: MutationQueueFactory? = nil,
        refresher: OAuthTokenRefresher,
        platform: GoogleOAuthPlatform
    ) {
        self.configurationStore = configurationStore
        self.tokenStore = tokenStore
        self.storeFactory = storeFactory
        self.transportFactory = transportFactory
        self.clientFactory = clientFactory
        self.mutationQueueFactory = mutationQueueFactory
        self.refresher = refresher
        self.platform = platform
    }

    /// Builds the production connector using UserDefaults, Keychain, SQLite,
    /// and the Google REST transport.
    public static func standard(
        applicationSupportURL: URL,
        configurationStore: any GmailAccountConfigurationStore,
        tokenStore: any TokenStore,
        googleClientID: String = GoogleOAuthClientID,
        platform: GoogleOAuthPlatform? = nil
    ) -> GmailAccountConnector {
        let refreshCoordinator = OAuthRefreshCoordinator()
        let refresher = OAuthTokenRefresher(
            clientID: googleClientID,
            tokenStore: tokenStore,
            coordinator: refreshCoordinator
        )
        let databaseURL = defaultStoreURL(applicationSupportURL: applicationSupportURL)
        let resolvedPlatform: GoogleOAuthPlatform = platform ?? {
            #if os(iOS)
            .iOS
            #else
            .macOS
            #endif
        }()
        return GmailAccountConnector(
            configurationStore: configurationStore,
            tokenStore: tokenStore,
            storeFactory: { _ in try SQLiteGmailAccountStore(databaseURL: databaseURL) },
            transportFactory: { _, accessTokenProvider in
                GmailAPITransport(accessTokenProvider: accessTokenProvider)
            },
            clientFactory: { _, transport in
                guard let transport = transport as? GmailAPITransport else { return nil }
                return GmailAPIClient(transport: transport)
            },
            mutationQueueFactory: { accountID in
                (
                    OfflineMutationQueueStorage.queue(accountID: accountID),
                    OfflineMutationQueueStorage.conflictStore(accountID: accountID)
                )
            },
            refresher: refresher,
            platform: resolvedPlatform
        )
    }

    /// The default per-device SQLite location for the canonical Gmail store.
    public static func defaultStoreURL(applicationSupportURL: URL) -> URL {
        applicationSupportURL.appendingPathComponent("Brev/Gmail/gmail.sqlite")
    }

    /// Provisions and connects a native Gmail account from a verified OAuth result.
    /// Token and metadata writes are rolled back if backend connection fails.
    public func provision(_ result: GoogleOAuthResult) async throws -> GmailConnectedAccount {
        guard let accountID = result.accountID else {
            throw GmailAccountConnectorError.missingGoogleSubject
        }
        guard !result.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GmailAccountConnectorError.missingEmail
        }

        let configuration = GoogleOAuthAccountConfiguration(
            subject: result.subject,
            email: result.email,
            hostedDomain: result.hostedDomain,
            grantedScopes: result.grantedScopes,
            platform: platform,
            providerMode: .gmailAPI,
            accessTokenExpiresAt: result.expiresAt,
            refreshTokenExpiresAt: result.refreshTokenExpiresAt
        )
        guard configuration.accountID == accountID else {
            throw GmailAccountConnectorError.configurationMismatch
        }

        let previousConfiguration = await configurationStore.configuration(for: accountID)
        let previousToken = await tokenStore.token(for: accountID)
        do {
            try await tokenStore.setToken(result.asToken(providerMode: .gmailAPI), for: accountID)
            try await configurationStore.setConfiguration(configuration)
            return try await connect(
                accountID: accountID,
                emailAddress: configuration.email,
                displayName: configuration.email,
                grantedScopes: configuration.grantedScopes
            )
        } catch {
            do {
                try await restore(
                    previousConfiguration,
                    previousToken,
                    installedConfiguration: configuration,
                    installedToken: result.asToken(providerMode: .gmailAPI),
                    accountID: accountID
                )
            } catch {
                throw GmailAccountConnectorError.provisioningRollbackFailed
            }
            throw error
        }
    }

    /// Restores a previously provisioned native Gmail account.
    public func restore(_ account: BrevAccount) async throws -> GmailConnectedAccount? {
        guard account.backendIdentifier == BrevAccount.gmailAPIBackendIdentifier else { return nil }
        guard let configuration = await configurationStore.configuration(for: account.id) else {
            throw GmailAccountConnectorError.configurationMismatch
        }
        guard configuration.providerMode == .gmailAPI,
              configuration.accountID == account.id
        else { throw GmailAccountConnectorError.configurationMismatch }
        guard await tokenStore.token(for: account.id) != nil else {
            throw GmailAccountConnectorError.missingToken
        }
        return try await connect(
            accountID: account.id,
            emailAddress: configuration.email,
            displayName: account.displayName,
            grantedScopes: configuration.grantedScopes
        )
    }

    /// Removes metadata, Keychain credentials, canonical records, and caches.
    public func remove(accountID: String) async throws {
        let store: any GmailAccountStore
        do {
            store = try storeFactory(accountID)
        } catch {
            throw GmailAccountConnectorError.removalCleanupFailed
        }
        do {
            try await store.removeAccount(accountID: accountID)
        } catch {
            throw GmailAccountConnectorError.removalCleanupFailed
        }
        if let stores = mutationQueueFactory?(accountID) {
            do {
                try await stores.queue.removeAll()
                try await stores.conflicts.removeAll()
            } catch {
                throw GmailAccountConnectorError.pendingCleanupFailed
            }
        }
        do {
            try await tokenStore.clearTokenChecked(for: accountID)
        } catch {
            throw GmailAccountConnectorError.removalCleanupFailed
        }
        await configurationStore.clearConfiguration(for: accountID)
    }

    private func connect(
        accountID: String,
        emailAddress: String,
        displayName: String,
        grantedScopes: Set<String> = []
    ) async throws -> GmailConnectedAccount {
        let account = BrevAccount(
            id: accountID,
            displayName: displayName,
            emailAddress: emailAddress,
            backendIdentifier: BrevAccount.gmailAPIBackendIdentifier,
            backendDisplayName: BrevAccount.gmailAPIBackendDisplayName
        )
        let store = try storeFactory(accountID)
        let accessTokenProvider = GmailOAuthAccessTokenProvider(
            accountID: accountID,
            tokenStore: tokenStore,
            refresher: refresher
        )
        let transport = transportFactory(accountID, accessTokenProvider)
        let client = clientFactory(accountID, transport)
        let reconciler = client.map {
            GmailSyncReconciler(client: $0, store: store, accountID: accountID)
        }
        let mutationStores = mutationQueueFactory?(accountID)
        let backend = GmailAPIBackend(
            account: account,
            transport: transport,
            store: store,
            client: client,
            grantedScopes: grantedScopes,
            syncReconciler: reconciler,
            offlineMutationQueue: mutationStores?.queue,
            offlineMutationConflictStore: mutationStores?.conflicts
        )
        try await backend.connect()
        return GmailConnectedAccount(account: account, backend: backend)
    }

    private func restore(
        _ configuration: GoogleOAuthAccountConfiguration?,
        _ token: Token?,
        installedConfiguration: GoogleOAuthAccountConfiguration,
        installedToken: Token,
        accountID: String
    ) async throws {
        do {
            if let token {
                try await tokenStore.setToken(token, for: accountID)
            } else {
                try await tokenStore.clearTokenChecked(for: accountID)
            }
            if let configuration {
                try await configurationStore.setConfiguration(configuration)
            } else {
                await configurationStore.clearConfiguration(for: accountID)
            }
        } catch {
            // Keep the newly-installed token and metadata together when a
            // previous state cannot be restored. This is the safest state for
            // a subsequent explicit retry and avoids a mixed credential pair.
            try? await tokenStore.setToken(installedToken, for: accountID)
            try? await configurationStore.setConfiguration(installedConfiguration)
            throw error
        }
    }
}
