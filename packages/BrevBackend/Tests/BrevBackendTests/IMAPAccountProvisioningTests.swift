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

@testable import BrevBackend
import Foundation
import Testing

@Suite("IMAP account provisioning")
struct IMAPAccountProvisioningTests {
    @Test("provisioning stores account configuration and credential")
    func provisioningStoresAccountConfigurationAndCredential() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "User@Example.ORG"
        )

        let account = try await provisioner.addAccount(
            emailAddress: " User@Example.ORG ",
            displayName: "",
            discovery: discovery,
            password: "app-password-123"
        )

        #expect(account.id == "imap-smtp:user@example.org")
        #expect(account.displayName == "user@example.org")
        #expect(account.emailAddress == "user@example.org")
        #expect(account.backendIdentifier == BrevAccount.imapSMTPBackendIdentifier)
        #expect(account.backendDisplayName == BrevAccount.imapSMTPBackendDisplayName)
        #expect(await accountStore.current == account)

        let configuration = try #require(
            await configurationStore.configuration(for: account.id)
        )
        #expect(configuration.incoming.host == "imap.example.org")
        #expect(configuration.outgoing.host == "smtp.example.org")
        #expect(configuration.credentialID == account.id)

        let credential = try #require(
            await credentialStore.credential(for: configuration.credentialID)
        )
        #expect(credential.incomingUsername == "User@example.org")
        #expect(credential.outgoingUsername == "User@example.org")
        #expect(credential.secret == "app-password-123")
        #expect(credential.authentication == .password)
    }

    @Test("provisioning stores optional ManageSieve endpoint")
    func provisioningStoresOptionalManageSieveEndpoint() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        var discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        discovery.manageSieve = MailServerSettings(
            kind: .imap,
            host: " SIEVE.Example.ORG. ",
            port: 4190,
            tlsMode: .implicit,
            authentication: .password
        )

        let account = try await provisioner.addAccount(
            emailAddress: "person@example.org",
            displayName: "Person",
            discovery: discovery,
            password: "app-password-123"
        )

        let configuration = try #require(
            await configurationStore.configuration(for: account.id)
        )
        #expect(configuration.manageSieve?.host == "sieve.example.org")
        #expect(configuration.manageSieve?.kind == .manageSieve)
        #expect(configuration.manageSieve?.port == 4190)
        #expect(configuration.manageSieve?.tlsMode == .implicit)
        #expect(configuration.manageSieve?.usernameTemplate == "%EMAILADDRESS%")
    }

    @Test("provisioning fails before storing account when credential storage cannot round trip")
    func provisioningFailsBeforeStoringAccountWhenCredentialStorageCannotRoundTrip() async {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = DroppingMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )

        await #expect(throws: IMAPAccountProvisioningError.credentialStorageUnavailable) {
            try await provisioner.addAccount(
                emailAddress: "person@example.org",
                displayName: "Person",
                discovery: discovery,
                password: "app-password-123"
            )
        }

        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("provisioning canonicalizes accepted server hosts before storing configuration")
    func provisioningCanonicalizesAcceptedServerHosts() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        var discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        discovery.incoming?.host = " IMAP.Example.ORG. "
        discovery.outgoing?.host = " SMTP.Example.ORG. "

        let account = try await provisioner.addAccount(
            emailAddress: "person@example.org",
            displayName: nil,
            discovery: discovery,
            password: "app-password-123"
        )

        let configuration = try #require(
            await configurationStore.configuration(for: account.id)
        )
        #expect(configuration.incoming.host == "imap.example.org")
        #expect(configuration.outgoing.host == "smtp.example.org")
    }

    @Test("username templates resolve separately for incoming and outgoing servers")
    func usernameTemplatesResolveSeparately() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "Person@icloud.com")
        )

        let account = try await provisioner.addAccount(
            emailAddress: "Person@icloud.com",
            displayName: "Person",
            discovery: discovery,
            password: "icloud-app-password"
        )

        let configuration = try #require(
            await configurationStore.configuration(for: account.id)
        )
        let credential = try #require(
            await credentialStore.credential(for: configuration.credentialID)
        )

        #expect(credential.incomingUsername == "Person")
        #expect(credential.outgoingUsername == "Person@icloud.com")
        #expect(credential.authentication == .appPassword)
    }

    @Test("credential usernames preserve local-part case and normalize only the domain")
    func credentialUsernamesPreserveLocalPartCaseAndNormalizeDomain() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "User.Name@Example.ORG"
        )

        let account = try await provisioner.addAccount(
            emailAddress: " User.Name@Example.ORG ",
            displayName: nil,
            discovery: discovery,
            password: "app-password-123"
        )

        #expect(account.id == "imap-smtp:user.name@example.org")

        let configuration = try #require(
            await configurationStore.configuration(for: account.id)
        )
        let credential = try #require(
            await credentialStore.credential(for: configuration.credentialID)
        )

        #expect(credential.incomingUsername == "User.Name@example.org")
        #expect(credential.outgoingUsername == "User.Name@example.org")
    }

    @Test("provisioning rejects XOAUTH2 profiles until OAuth setup exists")
    func rejectsXOAuth2ProfilesUntilOAuthSetupExists() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@outlook.com")
        )

        await #expect(throws: IMAPAccountProvisioningError.unsupportedAuthentication(.xoauth2)) {
            try await provisioner.addAccount(
                emailAddress: "person@outlook.com",
                displayName: "Person",
                discovery: discovery,
                password: "not-used"
            )
        }
        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@outlook.com") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@outlook.com") == nil)
    }

    @Test("provisioning rejects encrypted password profiles until challenge auth exists")
    func rejectsEncryptedPasswordProfilesUntilChallengeAuthExists() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        var discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        discovery.incoming?.authentication = .encryptedPassword

        await #expect(throws: IMAPAccountProvisioningError.unsupportedAuthentication(.encryptedPassword)) {
            try await provisioner.addAccount(
                emailAddress: "person@example.org",
                displayName: "Person",
                discovery: discovery,
                password: "not-used"
            )
        }
        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("provisioning rejects invalid server settings before storing credentials")
    func rejectsInvalidServerSettingsBeforeStoringCredentials() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        var discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        discovery.incoming?.host = "imap example.org"
        discovery.outgoing?.port = 0

        await #expect(throws: IMAPAccountProvisioningError.invalidIncomingServer) {
            try await provisioner.addAccount(
                emailAddress: "person@example.org",
                displayName: "Person",
                discovery: discovery,
                password: "not-used"
            )
        }
        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("provisioning rejects host unsafe server names before storing credentials")
    func rejectsHostUnsafeServerNamesBeforeStoringCredentials() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        var discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        discovery.incoming?.host = "imap_example.org"

        await #expect(throws: IMAPAccountProvisioningError.invalidIncomingServer) {
            try await provisioner.addAccount(
                emailAddress: "person@example.org",
                displayName: "Person",
                discovery: discovery,
                password: "not-used"
            )
        }
        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("provisioning rejects malformed email addresses before storing credentials")
    func rejectsMalformedEmailAddressesBeforeStoringCredentials() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )

        await #expect(throws: IMAPAccountProvisioningError.invalidEmailAddress) {
            try await provisioner.addAccount(
                emailAddress: "person @example..org",
                displayName: "Person",
                discovery: discovery,
                password: "not-used"
            )
        }
        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person @example..org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person @example..org") == nil)
    }

    @Test("provisioning rejects NUL passwords before storing credentials")
    func rejectsNULPasswordsBeforeStoringCredentials() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )

        await #expect(throws: IMAPAccountProvisioningError.invalidCredential) {
            try await provisioner.addAccount(
                emailAddress: "person@example.org",
                displayName: "Person",
                discovery: discovery,
                password: "app\u{0}password"
            )
        }
        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("provisioning rejects unsafe resolved usernames before storing credentials")
    func rejectsUnsafeResolvedUsernamesBeforeStoringCredentials() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        var discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        discovery.incoming?.usernameTemplate = "%EMAILADDRESS%\nBAD"

        await #expect(throws: IMAPAccountProvisioningError.invalidCredential) {
            try await provisioner.addAccount(
                emailAddress: "person@example.org",
                displayName: "Person",
                discovery: discovery,
                password: "app-password"
            )
        }
        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("removing provisioned account clears account configuration and credential")
    func removingProvisionedAccountClearsState() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        let account = try await provisioner.addAccount(
            emailAddress: "person@example.org",
            displayName: "Person",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            ),
            password: "secret"
        )

        await provisioner.removeAccount(account.id)

        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: account.id) == nil)
        #expect(await credentialStore.credential(for: account.id) == nil)
    }

    @Test("user defaults configuration store persists no password material")
    func userDefaultsConfigurationStorePersistsNoPasswordMaterial() async throws {
        let defaults = try Self.makeDefaults()
        let store = UserDefaultsIMAPAccountConfigurationStore(
            userDefaults: defaults,
            key: "imap.configurations"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: "imap-smtp:person@example.org",
            emailAddress: "person@example.org",
            displayName: "Person",
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 587,
                tlsMode: .startTLS,
                authentication: .password
            ),
            credentialID: "imap-smtp:person@example.org"
        )

        await store.setConfiguration(configuration)

        let restored = UserDefaultsIMAPAccountConfigurationStore(
            userDefaults: defaults,
            key: "imap.configurations"
        )
        #expect(await restored.configuration(for: configuration.accountID) == configuration)

        let data = try #require(defaults.data(forKey: "imap.configurations"))
        let persisted = String(data: data, encoding: .utf8) ?? ""
        #expect(!persisted.contains("secret"))
        #expect(!persisted.contains("password-123"))
    }

    @Test("keychain credential store round trips and clears credentials")
    func keychainCredentialStoreRoundTripsAndClearsCredentials() async throws {
        let credentialID = "credential-\(UUID().uuidString)"
        let store = KeychainMailCredentialStore(
            service: "app.brev.tests.mail-credentials.\(UUID().uuidString)"
        )
        let credential = MailAccountCredential(
            incomingUsername: "person",
            outgoingUsername: "person@example.org",
            secret: "app-password",
            authentication: .appPassword
        )

        try await store.setCredential(credential, for: credentialID)
        #expect(await store.credential(for: credentialID) == credential)

        await store.clearCredential(for: credentialID)
        #expect(await store.credential(for: credentialID) == nil)
    }

    @Test("connector provisions and connects an IMAP SMTP backend")
    func connectorProvisionsAndConnectsBackend() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let recorder = IMAPFolderListingRecorder()
        let smtpRecorder = SMTPValidationRecorder()
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { configuration, credential in
                await recorder.record(configuration: configuration, credential: credential)
                return [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "INBOX",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    )
                ]
            },
            validateOutgoingServer: { configuration, credential in
                await smtpRecorder.record(
                    configuration: configuration,
                    credential: credential
                )
            }
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "Person@Example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        let result = try await connector.provisionAndConnect(request)

        #expect(result.account.id == "imap-smtp:person@example.org")
        #expect(result.backend.account == result.account)
        #expect(try await result.backend.folders().map { $0.id } == ["INBOX"])
        #expect(await recorder.records.count == 1)
        #expect(await smtpRecorder.records.map(\.configuration.accountID) == [
            "imap-smtp:person@example.org",
        ])
        #expect(await smtpRecorder.records.map(\.credential.outgoingUsername) == [
            "Person@example.org",
        ])
        #expect(await accountStore.current == result.account)
    }

    @Test("connector validates IMAP and SMTP without persisting account material")
    func connectorValidatesIMAPAndSMTPWithoutPersistingAccountMaterial() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let recorder = IMAPFolderListingRecorder()
        let smtpRecorder = SMTPValidationRecorder()
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { configuration, credential in
                await recorder.record(configuration: configuration, credential: credential)
                return [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "INBOX",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            validateOutgoingServer: { configuration, credential in
                await smtpRecorder.record(
                    configuration: configuration,
                    credential: credential
                )
            }
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "Person@Example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        try await connector.validate(request)

        #expect(await recorder.records.map(\.configuration.accountID) == [
            "imap-smtp:person@example.org",
        ])
        #expect(await smtpRecorder.records.map(\.configuration.accountID) == [
            "imap-smtp:person@example.org",
        ])
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("standard connector factory provisions through injected IMAP and SMTP transports")
    func standardConnectorFactoryProvisionsThroughInjectedTransports() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let imapTransport = ProvisioningScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "* LIST (\\HasNoChildren \\Sent) \"/\" \"Sent\"",
            "A0002 OK LIST completed",
            "* STATUS \"INBOX\" (MESSAGES 12 UNSEEN 3)",
            "A0003 OK STATUS completed",
            "* STATUS \"Sent\" (MESSAGES 8 UNSEEN 0)",
            "A0004 OK STATUS completed",
            "A0005 OK [READ-WRITE] SELECT completed",
            "* SEARCH 91",
            "A0006 OK SEARCH completed",
            #"* 9 FETCH (UID 91 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "CI receipt" (("GitHub" NIL "noreply" "github.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-91@example.org>"))"#,
            "A0007 OK FETCH completed",
        ])
        let smtpTransport = ProvisioningScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250-smtp.example.org",
            "250-STARTTLS",
            "250 AUTH PLAIN",
            "220 Ready to start TLS",
            "250-smtp.example.org",
            "250 AUTH PLAIN",
            "235 Authentication successful",
            "221 Bye",
        ])
        let connector = IMAPAccountConnector.standard(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            imapTransportFactory: { imapTransport },
            smtpTransportFactory: { smtpTransport }
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        let result = try await connector.provisionAndConnect(request)

        #expect(result.backend.capabilities.contains(.serverSideSearch))
        #expect(result.backend.capabilities.contains(.folderCreate))
        #expect(result.backend.capabilities.contains(.idleSync))
        #expect(try await result.backend.folders().map(\.id) == ["INBOX", "Sent"])
        let serverResults = try await result.backend.search(SearchQuery(
            text: "receipt",
            folderID: "INBOX",
            execution: .serverOnly
        ))
        #expect(serverResults.map(\.id) == ["INBOX:91"])
        #expect(await imapTransport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"app-password\"",
            "A0002 LIST \"\" \"*\"",
            "A0003 STATUS \"INBOX\" (MESSAGES UNSEEN)",
            "A0004 STATUS \"Sent\" (MESSAGES UNSEEN)",
            "A0005 SELECT \"INBOX\" (CONDSTORE)",
            "A0006 UID SEARCH TEXT \"receipt\"",
            "A0007 UID FETCH 91 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(await smtpTransport.sentLines.prefix(4) == [
            "EHLO brev.local",
            "STARTTLS",
            "EHLO brev.local",
            "AUTH PLAIN AHBlcnNvbkBleGFtcGxlLm9yZwBhcHAtcGFzc3dvcmQ=",
        ])
        #expect(await smtpTransport.didUpgradeToTLS)
        #expect(await accountStore.current == result.account)
        #expect(await imapTransport.disconnectCount == 0)

        await result.backend.disconnect()

        #expect(await imapTransport.disconnectCount == 1)
    }

    @Test("connector rolls back stored IMAP account material when connect fails")
    func connectorRollsBackAccountMaterialWhenConnectFails() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                throw MailBackendError.network(underlying: "offline")
            }
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        await #expect(throws: (any Error).self) {
            try await connector.provisionAndConnect(request)
        }

        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("connector restores existing account material when replacement credential storage fails")
    func connectorRestoresExistingAccountMaterialWhenReplacementCredentialStorageFails() async throws {
        let accountID = "imap-smtp:person@example.org"
        let existingAccount = BrevAccount(
            id: accountID,
            displayName: "Existing Person",
            emailAddress: "person@example.org"
        )
        let existingConfiguration = IMAPAccountConfiguration(
            accountID: accountID,
            emailAddress: "person@example.org",
            displayName: "Existing Person",
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.old.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.old.example.org",
                port: 465,
                tlsMode: .implicit,
                authentication: .password
            ),
            credentialID: accountID
        )
        let existingCredential = MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "old-password",
            authentication: .password
        )
        let accountStore = InMemoryAccountStore(accounts: [existingAccount], current: existingAccount)
        let configurationStore = InMemoryIMAPAccountConfigurationStore(
            configurations: [existingConfiguration]
        )
        let credentialStore = DropFirstMailCredentialStore(
            credentials: [accountID: existingCredential]
        )
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in [] }
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Replacement Person",
            password: "new-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        await #expect(throws: IMAPAccountProvisioningError.credentialStorageUnavailable) {
            try await connector.provisionAndConnect(request)
        }

        #expect(await accountStore.accounts == [existingAccount])
        #expect(await accountStore.current == existingAccount)
        #expect(await configurationStore.configuration(for: accountID) == existingConfiguration)
        #expect(await credentialStore.credential(for: accountID) == existingCredential)
    }

    @Test("connector rolls back stored IMAP account material when SMTP validation fails")
    func connectorRollsBackAccountMaterialWhenSMTPValidationFails() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "INBOX",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    )
                ]
            },
            validateOutgoingServer: { _, _ in
                throw SMTPClientError.authenticationFailed("535 Authentication failed")
            }
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        await #expect(throws: SMTPClientError.authenticationFailed("535 Authentication failed")) {
            try await connector.provisionAndConnect(request)
        }

        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: "imap-smtp:person@example.org") == nil)
        #expect(await credentialStore.credential(for: "imap-smtp:person@example.org") == nil)
    }

    @Test("connector preserves existing IMAP account material when replacement connect fails")
    func connectorPreservesExistingAccountMaterialWhenReplacementConnectFails() async throws {
        let accountID = "imap-smtp:person@example.org"
        let existingAccount = BrevAccount(
            id: accountID,
            displayName: "Existing Person",
            emailAddress: "person@example.org"
        )
        let existingConfiguration = IMAPAccountConfiguration(
            accountID: accountID,
            emailAddress: "person@example.org",
            displayName: "Existing Person",
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.old.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.old.example.org",
                port: 465,
                tlsMode: .implicit,
                authentication: .password
            ),
            credentialID: accountID
        )
        let existingCredential = MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "old-working-password",
            authentication: .password
        )
        let accountStore = InMemoryAccountStore(accounts: [existingAccount], current: existingAccount)
        let configurationStore = InMemoryIMAPAccountConfigurationStore(configurations: [existingConfiguration])
        let credentialStore = InMemoryMailCredentialStore(credentials: [accountID: existingCredential])
        let folderCache = InMemoryIMAPFolderSnapshotCache()
        await folderCache.setSnapshot(
            IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
            ]),
            accountID: accountID
        )
        var replacementDiscovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        replacementDiscovery.incoming?.host = "imap.new.example.org"
        replacementDiscovery.outgoing?.host = "smtp.new.example.org"
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                throw MailBackendError.network(underlying: "new settings offline")
            },
            folderCache: folderCache
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Replacement Person",
            password: "bad-new-password",
            discovery: replacementDiscovery
        )

        await #expect(throws: (any Error).self) {
            try await connector.provisionAndConnect(request)
        }

        #expect(await accountStore.accounts == [existingAccount])
        #expect(await accountStore.current == existingAccount)
        #expect(await configurationStore.configuration(for: accountID) == existingConfiguration)
        #expect(await credentialStore.credential(for: accountID) == existingCredential)
        #expect(await folderCache.snapshot(accountID: accountID)?.folders.map(\.id) == ["INBOX"])
    }

    @Test("connector clears IMAP local stores when provisioned connect fails")
    func connectorClearsIMAPLocalStoresWhenProvisionedConnectFails() async throws {
        let accountID = "imap-smtp:person@example.org"
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let folderCache = InMemoryIMAPFolderSnapshotCache()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let draftStagingStore = InMemoryIMAPDraftStagingStore()
        await folderCache.setSnapshot(
            IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
            ]),
            accountID: accountID
        )
        await headerCache.setHeaders([
            MessageHeader(
                id: "INBOX:1",
                threadID: "<message-1@example.org>",
                folderID: "INBOX",
                from: Correspondent(email: "sender@example.org"),
                to: [Correspondent(email: "person@example.org")],
                cc: [],
                bcc: [],
                subject: "Cached",
                snippet: "Cached",
                date: Date(timeIntervalSince1970: 1_780_750_800),
                isRead: false,
                isFlagged: false,
                hasAttachments: false
            ),
        ], accountID: accountID, folderID: "INBOX")
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "Content-Type: text/plain\n\nCached"),
            accountID: accountID,
            messageID: "INBOX:1"
        )
        await draftStagingStore.setDraft(
            Draft(
                id: "draft-1",
                to: [Correspondent(email: "friend@example.org")],
                subject: "Draft",
                htmlBody: "<p>Draft</p>"
            ),
            accountID: accountID
        )
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                throw MailBackendError.network(underlying: "offline")
            },
            folderCache: folderCache,
            headerCache: headerCache,
            sourceCache: sourceCache,
            draftStagingStore: draftStagingStore
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        await #expect(throws: (any Error).self) {
            try await connector.provisionAndConnect(request)
        }

        #expect(await accountStore.accounts.isEmpty)
        #expect(await configurationStore.configuration(for: accountID) == nil)
        #expect(await credentialStore.credential(for: accountID) == nil)
        #expect(await folderCache.snapshot(accountID: accountID) == nil)
        #expect(await headerCache.snapshot(accountID: accountID, folderID: "INBOX") == nil)
        #expect(await sourceCache.source(accountID: accountID, messageID: "INBOX:1") == nil)
        #expect(await draftStagingStore.draft(accountID: accountID, draftID: "draft-1") == nil)
    }

    @Test("restore signals a retryable transient error (not re-auth) when the Keychain is locked")
    func connectorRestoreReportsTransientErrorWhenCredentialStoreLocked() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = LockedMailCredentialStore()
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap, host: "imap.example.org", port: 993,
                tlsMode: .implicit, authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp, host: "smtp.example.org", port: 465,
                tlsMode: .implicit, authentication: .password
            ),
            credentialID: account.id
        )
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            folderCache: InMemoryIMAPFolderSnapshotCache()
        )

        // A locked Keychain must not be mistaken for "no saved credential" —
        // that would force a spurious re-login on restart (#193 symptom 2).
        do {
            _ = try await connector.restore(account)
            Issue.record("expected restore to throw when the Keychain is locked")
        } catch let error as MailBackendError {
            guard case .credentialStoreUnavailable = error else {
                Issue.record("expected .credentialStoreUnavailable, got \(error)")
                return
            }
        }
    }

    @Test("restore requires re-authentication when no credential is stored and the store is available")
    func connectorRestoreRequiresReauthWhenCredentialMissing() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = DroppingMailCredentialStore() // available, returns nil
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap, host: "imap.example.org", port: 993,
                tlsMode: .implicit, authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp, host: "smtp.example.org", port: 465,
                tlsMode: .implicit, authentication: .password
            ),
            credentialID: account.id
        )
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            folderCache: InMemoryIMAPFolderSnapshotCache()
        )

        do {
            _ = try await connector.restore(account)
            Issue.record("expected restore to require re-authentication")
        } catch let error as MailBackendError {
            guard case .authenticationRequired = error else {
                Issue.record("expected .authenticationRequired, got \(error)")
                return
            }
        }
    }

    @Test("connector restores saved IMAP account with stored credentials")
    func connectorRestoresSavedIMAPAccount() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 465,
                tlsMode: .implicit,
                authentication: .password
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "app-password",
            authentication: .password
        )
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        try await credentialStore.setCredential(credential, for: account.id)
        let folderCache = InMemoryIMAPFolderSnapshotCache()
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "Sent",
                        displayName: "Sent",
                        delimiter: "/",
                        flags: ["\\Sent"],
                        role: .sent
                    )
                ]
            },
            listMessages: { _, _, folderID, pageToken, limit in
                #expect(folderID == "Sent")
                #expect(pageToken == nil)
                #expect(limit == 50)
                return IMAPMessageListingPage(messages: [
                    IMAPMessageListing(
                        uid: 7,
                        messageID: "<sent-7@example.org>",
                        subject: "Sent message",
                        from: Correspondent(email: "person@example.org"),
                        to: [Correspondent(email: "friend@example.org")],
                        cc: [],
                        bcc: [],
                        date: Date(timeIntervalSince1970: 1_780_750_800),
                        isRead: true,
                        isFlagged: false,
                        isAnswered: false
                    ),
                ])
            },
            folderCache: folderCache
        )

        let backend = try #require(try await connector.restore(account))

        #expect(try await backend.folders().map { $0.role } == [.sent])
        #expect(await folderCache.snapshot(accountID: account.id)?.folders.map(\.id) == ["Sent"])
        let messages = try await backend.messages(
            in: Folder(id: "Sent", name: "Sent", role: .sent),
            pageToken: nil
        )
        #expect(messages.headers.map(\.id) == ["Sent:7"])
    }

    @Test("connector attaches local search index to restored IMAP account")
    func connectorAttachesLocalSearchIndexToRestoredIMAPAccount() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 465,
                tlsMode: .implicit,
                authentication: .password
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "app-password",
            authentication: .password
        )
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        try await credentialStore.setCredential(credential, for: account.id)
        let metrics = LocalSearchIndexMetrics(
            databaseBytes: 4096,
            indexedHeaderCount: 7,
            cachedBodyCount: 3,
            searchDocumentCount: 7,
            syncedFolderCount: 2
        )
        let index = ProvisioningLocalSearchIndex(metrics: metrics)
        let factory = LocalSearchIndexFactoryRecorder(index: index)
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in [] },
            localSearchIndex: { accountID in factory.make(accountID: accountID) }
        )

        let backend = try #require(try await connector.restore(account))
        let health = await backend.syncHealth(for: MailSourceID(
            accountID: account.id,
            mailboxID: "INBOX"
        ))

        #expect(factory.accountIDs == [account.id])
        #expect(health.localSearchIndexMetrics == metrics)
        #expect(health.cacheSizeBytes == Int(metrics.databaseBytes))
    }

    @Test("connector validation does not create persistent local search index")
    func connectorValidationDoesNotCreatePersistentLocalSearchIndex() async throws {
        let factory = LocalSearchIndexFactoryRecorder(index: ProvisioningLocalSearchIndex())
        let connector = IMAPAccountConnector(
            accountStore: InMemoryAccountStore(),
            configurationStore: InMemoryIMAPAccountConfigurationStore(),
            credentialStore: InMemoryMailCredentialStore(),
            listFolders: { _, _ in [] },
            localSearchIndex: { accountID in factory.make(accountID: accountID) }
        )
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )

        try await connector.validate(request)

        #expect(factory.accountIDs.isEmpty)
    }

    @Test("connector refreshes XOAUTH2 token after restore authentication failure")
    func connectorRefreshesXOAuth2TokenAfterRestoreAuthenticationFailure() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let tokenStore = InMemoryTokenStore()
        let account = BrevAccount(
            id: "imap-smtp:person@gmail.com",
            displayName: "Person",
            emailAddress: "person@gmail.com"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.gmail.com",
                port: 993,
                tlsMode: .implicit,
                authentication: .xoauth2
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.gmail.com",
                port: 587,
                tlsMode: .startTLS,
                authentication: .xoauth2
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "person@gmail.com",
            outgoingUsername: "person@gmail.com",
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let storedToken = Token(
            accessToken: "expired-access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let refreshedToken = Token(
            accessToken: "fresh-access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        try await credentialStore.setCredential(credential, for: account.id)
        await tokenStore.setToken(storedToken, for: account.id)

        let recorder = RestoreCredentialRecorder()
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { configuration, credential in
                try await recorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            tokenStore: tokenStore,
            refreshOAuthToken: { accountID, configuration, tokenStore in
                #expect(accountID == account.id)
                #expect(configuration.incoming.host == "imap.gmail.com")
                #expect(await tokenStore.token(for: accountID)?.refreshToken == "refresh-token")
                return refreshedToken
            }
        )

        #expect(try await connector.restore(account) != nil)

        #expect(await recorder.records.map(\.credential.secret) == [
            "expired-access-token",
            "fresh-access-token",
        ])
        #expect(await credentialStore.credential(for: account.id)?.secret == "fresh-access-token")
        #expect(await tokenStore.token(for: account.id)?.accessToken == "fresh-access-token")
    }

    @Test("connector preserves XOAUTH2 refresh failure details")
    func connectorPreservesXOAuth2RefreshFailureDetails() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let tokenStore = InMemoryTokenStore()
        let account = BrevAccount(
            id: "imap-smtp:person@gmail.com",
            displayName: "Person",
            emailAddress: "person@gmail.com"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.gmail.com",
                port: 993,
                tlsMode: .implicit,
                authentication: .xoauth2
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.gmail.com",
                port: 587,
                tlsMode: .startTLS,
                authentication: .xoauth2
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "person@gmail.com",
            outgoingUsername: "person@gmail.com",
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        try await credentialStore.setCredential(credential, for: account.id)

        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                throw IMAPClientError.authenticationFailed("NO AUTHENTICATE failed")
            },
            tokenStore: tokenStore,
            refreshOAuthToken: { _, _, _ in
                throw OAuthRefreshError.missingRefreshToken
            }
        )

        do {
            _ = try await connector.restore(account)
            Issue.record("Expected the OAuth refresh failure to be rethrown.")
        } catch OAuthRefreshError.missingRefreshToken {
            // Expected.
        } catch {
            Issue.record("Expected OAuthRefreshError.missingRefreshToken, got \(error).")
        }

        #expect(await credentialStore.credential(for: account.id) == credential)
        #expect(await tokenStore.token(for: account.id) == nil)
    }

    @Test("connector restores IMAP account with cached folders when folder listing is temporarily unavailable")
    func connectorRestoresIMAPAccountWithCachedFoldersWhenFolderListingFails() async throws {
        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let folderCache = InMemoryIMAPFolderSnapshotCache()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 465,
                tlsMode: .implicit,
                authentication: .password
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "app-password",
            authentication: .password
        )
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        try await credentialStore.setCredential(credential, for: account.id)
        await folderCache.setSnapshot(
            IMAPFolderCacheSnapshot(
                folders: [inbox],
                folderDelimitersByID: ["INBOX": "/"]
            ),
            accountID: account.id
        )
        await headerCache.setHeaders(
            [
                MessageHeader(
                    id: "INBOX:42",
                    threadID: "INBOX:42",
                    folderID: "INBOX",
                    from: Correspondent(email: "sender@example.org"),
                    to: [Correspondent(email: "person@example.org")],
                    cc: [],
                    bcc: [],
                    subject: "Cached inbox",
                    snippet: "Available while offline",
                    date: Date(timeIntervalSince1970: 1_780_750_800),
                    isRead: false,
                    isFlagged: false,
                    hasAttachments: false
                ),
            ],
            accountID: account.id,
            folderID: "INBOX"
        )
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                throw IMAPClientError.transport("offline")
            },
            listMessages: { _, _, _, _, _ in
                throw IMAPClientError.transport("offline")
            },
            folderCache: folderCache,
            headerCache: headerCache
        )

        let backend = try #require(try await connector.restore(account))
        let messages = try await backend.messages(in: inbox, pageToken: nil)

        #expect(try await backend.folders() == [inbox])
        #expect(messages.headers.map(\.id) == ["INBOX:42"])
        // Cache-first restore keeps the immediate local snapshot usable even
        // when its independent background IMAP reconciliation later reports a
        // transient failure through sync health.
    }

    @Test("connector restore returns before pending mutation replay finishes")
    func connectorRestoreReturnsBeforePendingMutationReplayFinishes() async throws {
        enum RestoreRaceResult {
            case backend(IMAPSMTPBackend?)
            case failure(String)
            case timeout
        }

        let accountStore = InMemoryAccountStore()
        let configurationStore = InMemoryIMAPAccountConfigurationStore()
        let credentialStore = InMemoryMailCredentialStore()
        let queue = BlockingMutationQueue()
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 465,
                tlsMode: .implicit,
                authentication: .password
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "app-password",
            authentication: .password
        )
        await accountStore.add(account)
        await configurationStore.setConfiguration(configuration)
        try await credentialStore.setCredential(credential, for: account.id)
        let connector = IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "INBOX",
                        delimiter: "/",
                        flags: ["\\Inbox"],
                        role: .inbox
                    )
                ]
            },
            offlineMutationQueue: { _ in queue }
        )

        let restoreTask = Task { try await connector.restore(account) }
        let raceFinisher = OneShotContinuation<RestoreRaceResult>()
        let raceResult = await withCheckedContinuation { continuation in
            Task {
                do {
                    let backend = try await restoreTask.value
                    await raceFinisher.resume(
                        .backend(backend),
                        continuation: continuation
                    )
                } catch {
                    await raceFinisher.resume(
                        .failure(String(describing: error)),
                        continuation: continuation
                    )
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await raceFinisher.resume(.timeout, continuation: continuation)
            }
        }

        await queue.release()
        restoreTask.cancel()
        _ = try? await restoreTask.value

        switch raceResult {
        case .backend(let backend):
            #expect(try await backend?.folders().map(\.id) == ["INBOX"])
        case .failure(let error):
            Issue.record("Restore failed unexpectedly: \(error)")
        case .timeout:
            Issue.record("Restore waited for pending mutation replay before returning a backend.")
        }
    }

    @Test("connector skips restore for non IMAP SMTP accounts")
    func connectorSkipsNonIMAPSMTPAccounts() async throws {
        let connector = IMAPAccountConnector(
            accountStore: InMemoryAccountStore(),
            configurationStore: InMemoryIMAPAccountConfigurationStore(),
            credentialStore: InMemoryMailCredentialStore(),
            listFolders: { _, _ in [] }
        )
        let account = BrevAccount(
            id: "legacy",
            displayName: "Legacy",
            emailAddress: "legacy@example.org",
            backendIdentifier: "legacy-backend",
            backendDisplayName: "Legacy backend"
        )

        #expect(try await connector.restore(account) == nil)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "app.brev.tests.imap-configuration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor DroppingMailCredentialStore: MailCredentialStore {
    func credential(for credentialID: String) -> MailAccountCredential? {
        _ = credentialID
        return nil
    }

    func setCredential(
        _ credential: MailAccountCredential,
        for credentialID: String
    ) {
        _ = credential
        _ = credentialID
    }

    func clearCredential(for credentialID: String) {
        _ = credentialID
    }
}

/// Mimics a locked system Keychain: every read returns nil while reporting the
/// store is temporarily unavailable (so nil ≠ "no saved credential").
private actor LockedMailCredentialStore: MailCredentialStore {
    func credential(for credentialID: String) -> MailAccountCredential? {
        _ = credentialID
        return nil
    }

    func setCredential(
        _ credential: MailAccountCredential,
        for credentialID: String
    ) {
        _ = credential
        _ = credentialID
    }

    func clearCredential(for credentialID: String) {
        _ = credentialID
    }

    func isTemporarilyUnavailable() -> Bool { true }
}

private actor DropFirstMailCredentialStore: MailCredentialStore {
    private var credentials: [String: MailAccountCredential]
    private var shouldDropNextWrite = true

    init(credentials: [String: MailAccountCredential]) {
        self.credentials = credentials
    }

    func credential(for credentialID: String) -> MailAccountCredential? {
        credentials[credentialID]
    }

    func setCredential(
        _ credential: MailAccountCredential,
        for credentialID: String
    ) {
        if shouldDropNextWrite {
            shouldDropNextWrite = false
            return
        }
        credentials[credentialID] = credential
    }

    func clearCredential(for credentialID: String) {
        credentials.removeValue(forKey: credentialID)
    }
}

private final class LocalSearchIndexFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let index: ProvisioningLocalSearchIndex
    private var recordedAccountIDs: [BrevAccount.ID] = []

    init(index: ProvisioningLocalSearchIndex) {
        self.index = index
    }

    var accountIDs: [BrevAccount.ID] {
        lock.withLock { recordedAccountIDs }
    }

    func make(accountID: BrevAccount.ID) -> any MailLocalSearchIndex {
        lock.withLock {
            recordedAccountIDs.append(accountID)
        }
        return index
    }
}

private actor ProvisioningLocalSearchIndex: MailLocalSearchIndex {
    private let metricSnapshot: LocalSearchIndexMetrics?

    init(metrics: LocalSearchIndexMetrics? = nil) {
        metricSnapshot = metrics
    }

    func cachedHeaders(
        for folder: Folder,
        account: BrevAccount,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        _ = folder
        _ = account
        _ = pageToken
        return nil
    }

    func cachedRawMessage(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data? {
        _ = messageID
        _ = account
        return nil
    }

    func search(
        _ query: SearchQuery,
        account: BrevAccount,
        limit: Int
    ) async -> [MessageHeader] {
        _ = query
        _ = account
        _ = limit
        return []
    }

    func storeHeaders(
        _ headers: [MessageHeader],
        account: BrevAccount
    ) async {
        _ = headers
        _ = account
    }

    func storeRawMessage(
        _ data: Data,
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async {
        _ = data
        _ = messageID
        _ = account
    }

    func deleteMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        _ = messageIDs
        _ = account
    }

    func deleteRawMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        _ = messageIDs
        _ = account
    }

    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        account: BrevAccount
    ) async {
        _ = folderID
        _ = account
    }

    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async {
        _ = folderID
        _ = exceptMessageIDs
        _ = account
    }

    func clearFolder(
        folderID: Folder.ID,
        account: BrevAccount
    ) async {
        _ = folderID
        _ = account
    }

    func clearAccount(_ account: BrevAccount) async {
        _ = account
    }

    func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics? {
        _ = account
        return metricSnapshot
    }
}

private actor IMAPFolderListingRecorder {
    struct Record: Sendable {
        let configuration: IMAPAccountConfiguration
        let credential: MailAccountCredential
    }

    private(set) var records: [Record] = []

    func record(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) {
        records.append(Record(
            configuration: configuration,
            credential: credential
        ))
    }
}

private actor SMTPValidationRecorder {
    struct Record: Sendable {
        let configuration: IMAPAccountConfiguration
        let credential: MailAccountCredential
    }

    private(set) var records: [Record] = []

    func record(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) {
        records.append(Record(
            configuration: configuration,
            credential: credential
        ))
    }
}

private actor RestoreCredentialRecorder {
    struct Record: Sendable {
        let configuration: IMAPAccountConfiguration
        let credential: MailAccountCredential
    }

    private(set) var records: [Record] = []

    func listFolders(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) throws -> [IMAPFolderListing] {
        records.append(Record(
            configuration: configuration,
            credential: credential
        ))
        if credential.secret == "expired-access-token" {
            throw IMAPClientError.authenticationFailed("NO AUTHENTICATE failed")
        }
        return [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "INBOX",
                delimiter: "/",
                flags: ["\\Inbox"],
                role: .inbox
            ),
        ]
    }
}

private actor ProvisioningScriptedIMAPTransport: IMAPSessionTransport {
    private var lines: [String]
    private(set) var sentLines: [String] = []
    private(set) var disconnectCount = 0

    init(lines: [String]) {
        self.lines = lines
    }

    func connect(to server: MailServerSettings) async throws {
        #expect(server.kind == .imap)
    }

    func readLine() async throws -> String {
        guard !lines.isEmpty else {
            throw IMAPClientError.transport("No scripted IMAP response available.")
        }
        return lines.removeFirst()
    }

    func readData(maxLength: Int) async throws -> Data {
        _ = maxLength
        throw IMAPClientError.transport("No scripted IMAP data available.")
    }

    func writeLine(_ line: String) async throws {
        sentLines.append(line)
    }

    func writeData(_ data: Data) async throws {
        _ = data
        throw IMAPClientError.transport("No scripted IMAP data write expected.")
    }

    func disconnect() async {
        disconnectCount += 1
    }
}

private actor OneShotContinuation<Result: Sendable> {
    private var didResume = false

    func resume(
        _ result: Result,
        continuation: CheckedContinuation<Result, Never>
    ) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: result)
    }
}

private actor BlockingMutationQueue: OfflineMutationQueue {
    private var continuations: [CheckedContinuation<[PendingMutation], Never>] = []
    private var isReleased = false

    func enqueue(_ mutation: PendingMutation) async throws {
        _ = mutation
    }

    func pending() async throws -> [PendingMutation] {
        if isReleased { return [] }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func update(_ mutation: PendingMutation) async throws {
        _ = mutation
    }

    func remove(id: UUID) async throws {
        _ = id
    }

    func removeAll() async throws {}

    func release() {
        isReleased = true
        let pendingContinuations = continuations
        continuations = []
        for continuation in pendingContinuations {
            continuation.resume(returning: [])
        }
    }
}

private actor ProvisioningScriptedSMTPTransport: SMTPSessionTransport {
    private var lines: [String]
    private(set) var sentLines: [String] = []
    private(set) var didUpgradeToTLS = false

    init(lines: [String]) {
        self.lines = lines
    }

    func connect(to server: MailServerSettings) async throws {
        #expect(server.kind == .smtp)
    }

    func upgradeToTLS(server: MailServerSettings) async throws {
        #expect(server.kind == .smtp)
        didUpgradeToTLS = true
    }

    func readLine() async throws -> String {
        guard !lines.isEmpty else {
            throw SMTPClientError.transport("No scripted SMTP response available.")
        }
        return lines.removeFirst()
    }

    func writeLine(_ line: String) async throws {
        sentLines.append(line)
    }

    func disconnect() async {}
}
