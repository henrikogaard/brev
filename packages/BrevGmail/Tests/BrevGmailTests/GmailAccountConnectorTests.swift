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
@testable import BrevGmail
import Foundation
import Testing

@Suite("Gmail account connector", .serialized)
struct GmailAccountConnectorTests {
    @Test("UserDefaults configuration stores only non-secret metadata")
    func userDefaultsConfigurationPersistsMetadata() async throws {
        let suite = "BrevGmailConfig-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = Self.configuration()
        let store = UserDefaultsGmailAccountConfigurationStore(defaults: defaults, key: "config")

        try await store.setConfiguration(configuration)

        let reopened = UserDefaultsGmailAccountConfigurationStore(defaults: defaults, key: "config")
        #expect(await reopened.configuration(for: configuration.accountID) == configuration)
        let raw = defaults.data(forKey: "config")
        #expect(raw != nil)
        #expect(String(data: raw ?? Data(), encoding: .utf8)?.contains("refresh") == false)
    }

    @Test("provisioning uses Gmail API token metadata and stable subject identity")
    func provisioningUsesNativeTokenMetadata() async throws {
        let fixture = Fixture()
        let result = Self.oauthResult()
        let connected = try await fixture.connector.provision(result)

        #expect(connected.account.id == "gmail-api:stable-subject")
        #expect(connected.account.backendIdentifier == BrevAccount.gmailAPIBackendIdentifier)
        #expect(await fixture.tokens.token(for: connected.account.id)?.oauthMetadata?.providerMode == .gmailAPI)
        #expect(await fixture.tokens.token(for: connected.account.id)?.oauthMetadata?.googleSubject == "stable-subject")
        #expect(await fixture.configurations.configuration(for: connected.account.id)?.hostedDomain == "ogard.no")
    }

    @Test("provisioning rolls token and metadata back when connect fails")
    func provisioningRollsBackOnConnectFailure() async throws {
        let fixture = Fixture(transportError: .transportFailure)
        let accountID = "gmail-api:stable-subject"
        let oldToken = Token(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture)
        await fixture.tokens.setToken(oldToken, for: accountID)
        let oldConfiguration = Self.configuration(email: "old@example.com")
        try await fixture.configurations.setConfiguration(oldConfiguration)

        do {
            _ = try await fixture.connector.provision(Self.oauthResult())
            Issue.record("Expected Gmail connection failure")
        } catch {
            #expect(error as? GmailAPIError == .transportFailure)
        }

        #expect(await fixture.tokens.token(for: accountID) == oldToken)
        #expect(await fixture.configurations.configuration(for: accountID) == oldConfiguration)
    }

    @Test("provisioning reports a typed rollback failure and keeps the new pair recoverable")
    func provisioningRollbackFailureIsObservable() async throws {
        let configurations = InMemoryGmailAccountConfigurationStore()
        let tokens = RollbackFailingTokenStore()
        let accountID = "gmail-api:stable-subject"
        let oldToken = Token(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture)
        try await tokens.setToken(oldToken, for: accountID)
        try await configurations.setConfiguration(Self.configuration(email: "old@example.com"))
        await tokens.failRestoringPreviousToken()
        let connector = GmailAccountConnector(
            configurationStore: configurations,
            tokenStore: tokens,
            storeFactory: { _ in InMemoryGmailAccountStore() },
            transportFactory: { _, _ in StubGmailTransport(error: .transportFailure) },
            refresher: OAuthTokenRefresher(tokenStore: tokens),
            platform: .macOS
        )

        await #expect(throws: GmailAccountConnectorError.provisioningRollbackFailed) {
            try await connector.provision(Self.oauthResult())
        }
        #expect(await tokens.token(for: accountID)?.accessToken == "access")
        #expect(await configurations.configuration(for: accountID)?.email == "henrik@ogard.no")
    }

    @Test("restore reconnects a persisted Gmail API account")
    func restoreReconnectsPersistedAccount() async throws {
        let fixture = Fixture()
        let result = Self.oauthResult()
        let connected = try await fixture.connector.provision(result)
        await connected.backend.disconnect()

        let restored = try #require(try await fixture.connector.restore(connected.account))
        #expect(restored.account == connected.account)
        #expect(restored.backend.capabilities.contains(.providerAPI))
    }

    @Test("remove clears token, metadata, canonical store, and cache")
    func removeClearsAllAccountState() async throws {
        let fixture = Fixture()
        let connected = try await fixture.connector.provision(Self.oauthResult())
        try await fixture.store.replaceSnapshot(
            GmailAccountSnapshot(
                accountID: connected.account.id,
                state: GmailAccountState(accountID: connected.account.id, emailAddress: connected.account.emailAddress),
                labels: [],
                messages: []
            )
        )
        try await fixture.store.storeRawSource("Subject: cached", accountID: connected.account.id, messageID: "message")

        try await fixture.connector.remove(accountID: connected.account.id)

        #expect(await fixture.tokens.token(for: connected.account.id) == nil)
        #expect(await fixture.configurations.configuration(for: connected.account.id) == nil)
        #expect(try await fixture.store.accountState(accountID: connected.account.id) == nil)
        #expect(try await fixture.store.cachedRawSource(accountID: connected.account.id, messageID: "message") == nil)
    }

    @Test("expired Gmail token refreshes through the shared OAuth refresher")
    func expiredTokenRefreshes() async throws {
        let tokens = InMemoryTokenStore()
        let accountID = "gmail-api:refresh-subject"
        await tokens.setToken(
            Token(
                accessToken: "expired",
                refreshToken: "refresh",
                expiresAt: Date(timeIntervalSinceNow: -60),
                oauthMetadata: OAuthTokenMetadata(providerMode: .gmailAPI, googleSubject: "refresh-subject")
            ),
            for: accountID
        )
        MockURLProtocol.handler = { _ in
            MockURLProtocol.response(statusCode: 200, body: #"{"access_token":"fresh","expires_in":3600}"#)
        }
        let session = MockURLProtocol.session()
        let refresher = OAuthTokenRefresher(
            clientID: "test-client",
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            urlSession: session,
            tokenStore: tokens
        )
        let provider = GmailOAuthAccessTokenProvider(
            accountID: accountID,
            tokenStore: tokens,
            refresher: refresher
        )

        #expect(try await provider.accessToken() == "fresh")
        #expect(await tokens.token(for: accountID)?.accessToken == "fresh")
    }

    @Test("revoked Google refresh credentials surface provider-neutral reauthentication")
    func revokedRefreshCredentialRequiresReauthentication() async throws {
        let tokens = InMemoryTokenStore()
        let accountID = "gmail-api:revoked-subject"
        await tokens.setToken(
            Token(
                accessToken: "expired",
                refreshToken: "revoked-refresh",
                expiresAt: Date(timeIntervalSinceNow: -60),
                oauthMetadata: OAuthTokenMetadata(providerMode: .gmailAPI, googleSubject: "revoked-subject")
            ),
            for: accountID
        )
        MockURLProtocol.handler = { _ in
            MockURLProtocol.response(statusCode: 400, body: #"{"error":"invalid_grant"}"#)
        }
        let refresher = OAuthTokenRefresher(
            clientID: "test-client",
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            urlSession: MockURLProtocol.session(),
            tokenStore: tokens
        )
        let provider = GmailOAuthAccessTokenProvider(
            accountID: accountID,
            tokenStore: tokens,
            refresher: refresher
        )

        await #expect(throws: GmailAPIError.reauthenticationRequired) {
            try await provider.accessToken()
        }
    }

    @Test("account removal keeps credentials when canonical SQLite cleanup fails")
    func removalFailureIsRetryableAndDoesNotClearMetadata() async throws {
        let configurations = InMemoryGmailAccountConfigurationStore()
        let tokens = InMemoryTokenStore()
        let accountID = "gmail-api:cleanup-failure"
        try await configurations.setConfiguration(
            GoogleOAuthAccountConfiguration(
                subject: "cleanup-failure",
                email: "cleanup@example.com",
                platform: .macOS,
                providerMode: .gmailAPI
            )
        )
        await tokens.setToken(Token(accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture), for: accountID)
        let connector = GmailAccountConnector(
            configurationStore: configurations,
            tokenStore: tokens,
            storeFactory: { _ in FailingRemovalStore() },
            transportFactory: { _, _ in StubGmailTransport() },
            refresher: OAuthTokenRefresher(tokenStore: tokens),
            platform: .macOS
        )

        await #expect(throws: GmailAccountConnectorError.removalCleanupFailed) {
            try await connector.remove(accountID: accountID)
        }
        #expect(await configurations.configuration(for: accountID) != nil)
        #expect(await tokens.token(for: accountID) != nil)
    }

    @Test("account removal surfaces Keychain deletion failure and preserves retry state")
    func removalTokenDeletionFailureIsRetryable() async throws {
        let configurations = InMemoryGmailAccountConfigurationStore()
        let tokens = FailingClearTokenStore()
        let accountID = "gmail-api:clear-failure"
        try await configurations.setConfiguration(
            GoogleOAuthAccountConfiguration(
                subject: "clear-failure",
                email: "clear@example.com",
                platform: .macOS,
                providerMode: .gmailAPI
            )
        )
        await tokens.setToken(Token(accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture), for: accountID)
        let connector = GmailAccountConnector(
            configurationStore: configurations,
            tokenStore: tokens,
            storeFactory: { _ in InMemoryGmailAccountStore() },
            transportFactory: { _, _ in StubGmailTransport() },
            refresher: OAuthTokenRefresher(tokenStore: tokens),
            platform: .macOS
        )

        await #expect(throws: GmailAccountConnectorError.removalCleanupFailed) {
            try await connector.remove(accountID: accountID)
        }
        #expect(await configurations.configuration(for: accountID) != nil)
        #expect(await tokens.token(for: accountID) != nil)
    }

    private static func oauthResult() -> GoogleOAuthResult {
        GoogleOAuthResult(
            accessToken: "access",
            refreshToken: "refresh",
            email: "henrik@ogard.no",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            subject: "stable-subject",
            hostedDomain: "ogard.no",
            grantedScopes: ["openid", "email", "https://mail.google.com/"]
        )
    }

    private static func configuration(email: String = "henrik@ogard.no") -> GoogleOAuthAccountConfiguration {
        GoogleOAuthAccountConfiguration(
            subject: "stable-subject",
            email: email,
            hostedDomain: "ogard.no",
            grantedScopes: ["openid", "email"],
            platform: .macOS,
            providerMode: .gmailAPI
        )
    }
}

private struct Fixture {
    let configurations: InMemoryGmailAccountConfigurationStore
    let tokens: InMemoryTokenStore
    let store: InMemoryGmailAccountStore
    let connector: GmailAccountConnector

    init(transportError: GmailAPIError? = nil) {
        let configurations = InMemoryGmailAccountConfigurationStore()
        let tokens = InMemoryTokenStore()
        let store = InMemoryGmailAccountStore()
        let refresher = OAuthTokenRefresher(tokenStore: tokens)
        let connector = GmailAccountConnector(
            configurationStore: configurations,
            tokenStore: tokens,
            storeFactory: { _ in store },
            transportFactory: { _, _ in
                StubGmailTransport(error: transportError)
            },
            refresher: refresher,
            platform: .macOS
        )
        self.configurations = configurations
        self.tokens = tokens
        self.store = store
        self.connector = connector
    }
}

private actor InMemoryTokenStore: TokenStore {
    private var values: [String: Token] = [:]

    func token(for accountID: String) -> Token? { values[accountID] }
    func setToken(_ token: Token, for accountID: String) { values[accountID] = token }
    func clearToken(for accountID: String) { values[accountID] = nil }
}

private actor RollbackFailingTokenStore: TokenStore {
    private var values: [String: Token] = [:]
    private var shouldFailRestoringPreviousToken = false

    func token(for accountID: String) -> Token? { values[accountID] }

    func setToken(_ token: Token, for accountID: String) throws {
        if shouldFailRestoringPreviousToken, token.accessToken == "old" {
            throw TestTokenStoreError.writeFailed
        }
        values[accountID] = token
    }

    func clearToken(for accountID: String) { values[accountID] = nil }

    func failRestoringPreviousToken() { shouldFailRestoringPreviousToken = true }
}

private actor FailingClearTokenStore: TokenStore {
    private var values: [String: Token] = [:]

    func token(for accountID: String) -> Token? { values[accountID] }
    func setToken(_ token: Token, for accountID: String) { values[accountID] = token }
    func clearToken(for accountID: String) { values[accountID] = nil }
    func clearTokenChecked(for _: String) throws { throw TestTokenStoreError.deleteFailed }
}

private enum TestTokenStoreError: Error {
    case writeFailed
    case deleteFailed
}

private actor StubGmailTransport: GmailAPITransporting {
    let error: GmailAPIError?

    init(error: GmailAPIError? = nil) { self.error = error }

    func profile() async throws -> GmailProfile {
        if let error { throw error }
        return GmailProfile(emailAddress: "henrik@ogard.no", historyID: "1")
    }

    func listLabels() async throws -> [GmailLabel] {
        if let error { throw error }
        return [GmailLabel(id: "INBOX", name: "Inbox", type: "system")]
    }

    func listMessages(labelID _: String?, query _: String?, pageToken _: String?,
                      maxResults _: Int) async throws -> GmailMessagePage {
        if let error { throw error }
        return GmailMessagePage()
    }

    func getMessage(messageID _: String, format _: GmailMessageFormat) async throws -> GmailMessage {
        if let error { throw error }
        return GmailMessage(id: "message", threadID: "thread", labelIDs: ["INBOX"])
    }

    func getAttachment(messageID _: String, attachmentID _: String) async throws -> GmailAttachment {
        if let error { throw error }
        return GmailAttachment(id: "attachment", messageID: "message", data: "")
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) -> (Data, URLResponse))?

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func response(statusCode: Int, body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://oauth2.googleapis.com/token")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}

private actor FailingRemovalStore: GmailAccountStore {
    func removeAccount(accountID _: String) async throws { throw GmailAccountStoreError.databaseFailure }
    func accountState(accountID _: String) async throws -> GmailAccountState? { nil }
    func replaceSnapshot(_: GmailAccountSnapshot) async throws {}
    func apply(_: GmailStoreDelta) async throws {}
    func messages(accountID _: String) async throws -> [GmailMessage] { [] }
    func message(accountID _: String, messageID _: String) async throws -> GmailMessage? { nil }
    func labels(accountID _: String) async throws -> [GmailLabel] { [] }
    func messageLabelIDs(accountID _: String, messageID _: String) async throws -> [String] { [] }
}
