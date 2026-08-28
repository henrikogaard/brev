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

/// Live provider smoke tests.
///
/// These tests require real IMAP/SMTP credentials supplied via environment
/// variables. They are intentionally excluded from the default test run and
/// silently pass when the variables are absent.
///
/// Required env vars:
///   BREV_LIVE_MAIL_EMAIL      — e.g. user@example.com
///   BREV_LIVE_MAIL_PASSWORD   — IMAP/SMTP password or app password
///   BREV_LIVE_IMAP_HOST       — e.g. imap.example.com
///   BREV_LIVE_SMTP_HOST       — e.g. smtp.example.com
///
/// Optional env vars (override defaults):
///   BREV_LIVE_IMAP_PORT       — defaults to 993
///   BREV_LIVE_SMTP_PORT       — defaults to 587
///   BREV_LIVE_TLS_MODE        — "implicit" (default for IMAP) or "starttls"
///
/// Run with:
///   BREV_LIVE_MAIL_EMAIL=... swift test --package-path packages/BrevBackend
///
/// SECURITY: Never commit real credentials. These variables must only be
/// provided in CI secrets or a local shell session.

@testable import BrevBackend
import Foundation
import Testing

// MARK: - Credential helper

private struct LiveCredentials {
    let email: String
    let password: String
    let imapHost: String
    let smtpHost: String
    let imapPort: UInt16
    let smtpPort: UInt16
    let imapTLSMode: MailServerTLSMode
    let smtpTLSMode: MailServerTLSMode

    static func load() -> LiveCredentials? {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["BREV_LIVE_MAIL_EMAIL"],
              let password = env["BREV_LIVE_MAIL_PASSWORD"],
              let imapHost = env["BREV_LIVE_IMAP_HOST"],
              let smtpHost = env["BREV_LIVE_SMTP_HOST"]
        else { return nil }

        let imapPort = env["BREV_LIVE_IMAP_PORT"].flatMap { UInt16($0) } ?? 993
        let smtpPort = env["BREV_LIVE_SMTP_PORT"].flatMap { UInt16($0) } ?? 587
        let tlsModeString = env["BREV_LIVE_TLS_MODE"] ?? "implicit"
        let imapTLSMode: MailServerTLSMode = tlsModeString == "starttls" ? .startTLS : .implicit
        let smtpTLSMode: MailServerTLSMode = smtpPort == 465 ? .implicit : .startTLS

        return LiveCredentials(
            email: email,
            password: password,
            imapHost: imapHost,
            smtpHost: smtpHost,
            imapPort: imapPort,
            smtpPort: smtpPort,
            imapTLSMode: imapTLSMode,
            smtpTLSMode: smtpTLSMode
        )
    }

    static let accountID = "live-test-account"
    static let credentialID = "live-test-credential"

    func configuration() -> IMAPAccountConfiguration {
        IMAPAccountConfiguration(
            accountID: Self.accountID,
            emailAddress: email,
            displayName: "Live Test",
            incoming: MailServerSettings(
                kind: .imap,
                host: imapHost,
                port: imapPort,
                tlsMode: imapTLSMode,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: smtpHost,
                port: smtpPort,
                tlsMode: smtpTLSMode,
                authentication: .password
            ),
            credentialID: Self.credentialID
        )
    }

    func credential() -> MailAccountCredential {
        MailAccountCredential(
            incomingUsername: email,
            outgoingUsername: email,
            secret: password,
            authentication: .password
        )
    }
}

// MARK: - Tests

@Suite("Live provider smoke tests")
struct LiveProviderTests {
    @Test("live: IMAP client connects and lists folders")
    func liveIMAPConnectsAndListsFolders() async throws {
        guard let creds = LiveCredentials.load() else { return }

        let client = IMAPSessionClient(transport: NetworkIMAPSessionTransport())
        let folders = try await client.loginAndListFolders(
            configuration: creds.configuration(),
            credential: creds.credential()
        )

        #expect(!folders.isEmpty, "Expected at least one folder from a live server")
        #expect(folders.contains { $0.role == .inbox }, "Expected an Inbox folder")
    }

    @Test("live: IMAP client lists first page of inbox messages")
    func liveIMAPListsInboxMessages() async throws {
        guard let creds = LiveCredentials.load() else { return }

        let client = IMAPSessionClient(transport: NetworkIMAPSessionTransport())
        let page = try await client.loginAndListMessages(
            configuration: creds.configuration(),
            credential: creds.credential(),
            folderPath: "INBOX",
            limit: 10
        )

        // The inbox may be empty; just verify the call succeeds without throwing.
        _ = page.messages
        _ = page.uidValidity
    }

    @Test("live: IMAP client searches inbox")
    func liveIMAPSearchesInbox() async throws {
        guard let creds = LiveCredentials.load() else { return }

        let client = IMAPSessionClient(transport: NetworkIMAPSessionTransport())
        let results = try await client.loginAndSearchMessages(
            configuration: creds.configuration(),
            credential: creds.credential(),
            folderPath: "INBOX",
            query: SearchQuery(text: ""),
            limit: 5
        )

        _ = results
    }

    @Test("live: SMTP client validates credentials")
    func liveSMTPValidatesCredentials() async throws {
        guard let creds = LiveCredentials.load() else { return }

        let client = SMTPSessionClient(transport: NetworkSMTPSessionTransport())
        try await client.loginAndValidateCredentials(
            configuration: creds.configuration(),
            credential: creds.credential()
        )
    }

    @Test("live: backend connects, lists folders, and loads headers")
    func liveBackendConnectsAndLoadsHeaders() async throws {
        guard let creds = LiveCredentials.load() else { return }

        let account = BrevAccount(
            id: LiveCredentials.accountID,
            displayName: "Live Test",
            emailAddress: creds.email,
            backendIdentifier: BrevAccount.imapSMTPBackendIdentifier
        )
        let accountStore = InMemoryAccountStore(accounts: [account])
        let configStore = InMemoryIMAPAccountConfigurationStore(
            configurations: [creds.configuration()]
        )
        let credentialStore = InMemoryMailCredentialStore(
            credentials: [LiveCredentials.credentialID: creds.credential()]
        )

        let connector = IMAPAccountConnector.standard(
            accountStore: accountStore,
            configurationStore: configStore,
            credentialStore: credentialStore,
            folderCache: nil,
            headerCache: nil,
            sourceCache: nil
        )

        guard let backend = try await connector.restore(account) else {
            Issue.record("restore returned nil for live account")
            return
        }

        let folders = try await backend.folders()
        #expect(!folders.isEmpty, "Expected at least one folder")

        if let inbox = folders.first(where: { $0.role == FolderRole.inbox }) {
            let (headers, _) = try await backend.messages(in: inbox, pageToken: nil as String?)
            _ = headers
        }
    }
}
