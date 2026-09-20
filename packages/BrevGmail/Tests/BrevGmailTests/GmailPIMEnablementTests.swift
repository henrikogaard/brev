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

@Suite("Gmail PIM enablement", .serialized)
struct GmailPIMEnablementTests {
    private static let accountID = "gmail-api:subject-1"
    private static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
    private static let contactsScope = "https://www.googleapis.com/auth/contacts.readonly"

    // MARK: - Doubles

    private actor InMemoryTokenStore: TokenStore {
        var values: [String: Token] = [:]

        func token(for accountID: String) -> Token? { values[accountID] }
        func setToken(_ token: Token, for accountID: String) { values[accountID] = token }
        func clearToken(for accountID: String) { values[accountID] = nil }
    }

    private actor StubTransport: GmailAPITransporting {
        func profile() async throws -> GmailProfile {
            GmailProfile(emailAddress: "henrik@gmail.com", historyID: "1")
        }

        func listLabels() async throws -> [GmailLabel] {
            [GmailLabel(id: "INBOX", name: "Inbox", type: "system")]
        }

        func listMessages(
            labelID _: String?,
            query _: String?,
            pageToken _: String?,
            maxResults _: Int
        ) async throws -> GmailMessagePage {
            GmailMessagePage()
        }

        func getMessage(messageID _: String, format _: GmailMessageFormat) async throws -> GmailMessage {
            GmailMessage(id: "m", threadID: "t", labelIDs: ["INBOX"])
        }

        func getAttachment(messageID _: String, attachmentID _: String) async throws -> GmailAttachment {
            GmailAttachment(id: "a", messageID: "m", data: "")
        }
    }

    // MARK: - Fixture

    private struct Fixture {
        let configurations: InMemoryGmailAccountConfigurationStore
        let tokens: InMemoryTokenStore
        let connector: GmailAccountConnector

        init() {
            let configurations = InMemoryGmailAccountConfigurationStore()
            let tokens = InMemoryTokenStore()
            connector = GmailAccountConnector(
                configurationStore: configurations,
                tokenStore: tokens,
                storeFactory: { _ in InMemoryGmailAccountStore() },
                transportFactory: { _, _ in StubTransport() },
                refresher: OAuthTokenRefresher(tokenStore: tokens),
                platform: .macOS
            )
            self.configurations = configurations
            self.tokens = tokens
        }

        func installAccount(
            subject: String = "subject-1",
            grantedScopes: Set<String> = ["openid", "email", "https://mail.google.com/"]
        ) async throws {
            try await configurations.setConfiguration(
                GoogleOAuthAccountConfiguration(
                    subject: subject,
                    email: "henrik@gmail.com",
                    grantedScopes: grantedScopes,
                    platform: .macOS,
                    providerMode: .gmailAPI
                )
            )
            try await tokens.setToken(
                Token(
                    accessToken: "working-access",
                    refreshToken: "working-refresh",
                    expiresAt: .distantFuture
                ),
                for: accountID
            )
        }
    }

    private static func oauthResult(
        subject: String = "subject-1",
        grantedScopes: Set<String>
    ) -> GoogleOAuthResult {
        GoogleOAuthResult(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            email: "henrik@gmail.com",
            expiresAt: .distantFuture,
            subject: subject,
            grantedScopes: grantedScopes
        )
    }

    // MARK: - Tests

    @Test("enablement requests the union of existing and feature scopes")
    func enablementRequestsScopeUnion() async throws {
        let fixture = Fixture()
        try await fixture.installAccount()
        var requested: Set<String> = []

        _ = try await fixture.connector.enablePIMFeature(
            accountID: Self.accountID,
            additionalScopes: [Self.calendarScope],
            authorize: { scopes in
                requested = scopes
                return Self.oauthResult(grantedScopes: scopes)
            }
        )

        #expect(requested == [
            "openid",
            "email",
            "https://mail.google.com/",
            Self.calendarScope,
        ])
    }

    @Test("a fully granted authorization swaps token and metadata")
    func fullGrantSwapsCredential() async throws {
        let fixture = Fixture()
        try await fixture.installAccount()

        let updated = try await fixture.connector.enablePIMFeature(
            accountID: Self.accountID,
            additionalScopes: [Self.calendarScope],
            authorize: { scopes in
                Self.oauthResult(grantedScopes: scopes)
            }
        )

        #expect(updated.grantedScopes.contains(Self.calendarScope))
        #expect(updated.grantedScopes.contains("https://mail.google.com/"))
        let token = await fixture.tokens.token(for: Self.accountID)
        #expect(token?.accessToken == "new-access")
        #expect(token?.refreshToken == "new-refresh")
        let stored = await fixture.configurations.configuration(for: Self.accountID)
        #expect(stored?.grantedScopes == updated.grantedScopes)
    }

    @Test("an identity mismatch keeps the working credential")
    func identityMismatchKeepsCredential() async throws {
        let fixture = Fixture()
        try await fixture.installAccount()

        await #expect(throws: GmailAccountConnectorError.grantIdentityMismatch) {
            try await fixture.connector.enablePIMFeature(
                accountID: Self.accountID,
                additionalScopes: [Self.calendarScope],
                authorize: { scopes in
                    Self.oauthResult(subject: "different-subject", grantedScopes: scopes)
                }
            )
        }

        let token = await fixture.tokens.token(for: Self.accountID)
        #expect(token?.accessToken == "working-access")
        let stored = await fixture.configurations.configuration(for: Self.accountID)
        #expect(stored?.grantedScopes.contains(Self.calendarScope) == false)
    }

    @Test("a partial grant keeps the working credential")
    func partialGrantKeepsCredential() async throws {
        let fixture = Fixture()
        try await fixture.installAccount()

        await #expect(throws: GmailAccountConnectorError.grantScopesMissing) {
            try await fixture.connector.enablePIMFeature(
                accountID: Self.accountID,
                additionalScopes: [Self.calendarScope, Self.contactsScope],
                authorize: { scopes in
                    // Google granted Calendar but not Contacts.
                    Self.oauthResult(grantedScopes: scopes.subtracting([Self.contactsScope]))
                }
            )
        }

        let token = await fixture.tokens.token(for: Self.accountID)
        #expect(token?.accessToken == "working-access")
        #expect(token?.refreshToken == "working-refresh")
    }

    @Test("a grant that loses mail access is never installed")
    func grantLosingMailScopeIsRejected() async throws {
        let fixture = Fixture()
        try await fixture.installAccount()

        await #expect(throws: GmailAccountConnectorError.grantScopesMissing) {
            try await fixture.connector.enablePIMFeature(
                accountID: Self.accountID,
                additionalScopes: [Self.calendarScope],
                authorize: { _ in
                    Self.oauthResult(grantedScopes: ["openid", "email", Self.calendarScope])
                }
            )
        }

        let token = await fixture.tokens.token(for: Self.accountID)
        #expect(token?.accessToken == "working-access")
    }

    @Test("cancellation propagates and stores nothing")
    func cancellationStoresNothing() async throws {
        let fixture = Fixture()
        try await fixture.installAccount()

        await #expect(throws: GoogleOAuthFlowError.userCancelled) {
            try await fixture.connector.enablePIMFeature(
                accountID: Self.accountID,
                additionalScopes: [Self.calendarScope],
                authorize: { _ in throw GoogleOAuthFlowError.userCancelled }
            )
        }

        let token = await fixture.tokens.token(for: Self.accountID)
        #expect(token?.accessToken == "working-access")
    }

    @Test("enablement requires a stored Gmail API configuration")
    func missingConfigurationFails() async {
        let fixture = Fixture()

        await #expect(throws: GmailAccountConnectorError.configurationMismatch) {
            try await fixture.connector.enablePIMFeature(
                accountID: Self.accountID,
                additionalScopes: [Self.calendarScope],
                authorize: { scopes in Self.oauthResult(grantedScopes: scopes) }
            )
        }
    }
}
