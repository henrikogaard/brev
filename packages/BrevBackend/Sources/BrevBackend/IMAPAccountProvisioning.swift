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
import Security

public struct IMAPAccountConfiguration: Sendable, Hashable, Codable {
    public let accountID: String
    public let emailAddress: String
    public let displayName: String
    public let incoming: MailServerSettings
    public let outgoing: MailServerSettings
    public let manageSieve: MailServerSettings?
    public let credentialID: String

    public init(
        accountID: String,
        emailAddress: String,
        displayName: String,
        incoming: MailServerSettings,
        outgoing: MailServerSettings,
        manageSieve: MailServerSettings? = nil,
        credentialID: String
    ) {
        self.accountID = accountID
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.incoming = incoming
        self.outgoing = outgoing
        self.manageSieve = manageSieve
        self.credentialID = credentialID
    }
}

public struct IMAPAccountSetupRequest: Sendable, Hashable {
    public let emailAddress: String
    public let displayName: String?
    public let password: String
    public let discovery: MailAccountDiscoveryResult

    public init(
        emailAddress: String,
        displayName: String?,
        password: String,
        discovery: MailAccountDiscoveryResult
    ) {
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.password = password
        self.discovery = discovery
    }
}

/// Account setup request for an OAuth2-authenticated IMAP/SMTP account.
///
/// Unlike password-based setup, the caller obtains the access token via an
/// interactive browser flow (e.g. `GoogleOAuthFlow`) and then constructs
/// this request with the resulting short-lived bearer token. The token is
/// stored as the credential secret with `.xoauth2` authentication.
///
/// Server settings for known providers:
/// - Gmail IMAP: `imap.gmail.com:993` implicit TLS
/// - Gmail SMTP: `smtp.gmail.com:587` STARTTLS
/// - Outlook IMAP: `outlook.office365.com:993` implicit TLS
/// - Outlook SMTP: `smtp.office365.com:587` STARTTLS
public struct IMAPOAuthSetupRequest: Sendable {
    public let emailAddress: String
    public let displayName: String?
    public let incoming: MailServerSettings
    public let outgoing: MailServerSettings
    /// Short-lived OAuth2 access token obtained from the provider's token endpoint.
    public let accessToken: String

    public init(
        emailAddress: String,
        displayName: String? = nil,
        incoming: MailServerSettings,
        outgoing: MailServerSettings,
        accessToken: String
    ) {
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.incoming = incoming
        self.outgoing = outgoing
        self.accessToken = accessToken
    }
}

public protocol IMAPAccountConfigurationStore: Sendable {
    func configuration(for accountID: String) async -> IMAPAccountConfiguration?
    func setConfiguration(_ configuration: IMAPAccountConfiguration) async
    func clearConfiguration(for accountID: String) async
}

public actor InMemoryIMAPAccountConfigurationStore: IMAPAccountConfigurationStore {
    private var configurations: [String: IMAPAccountConfiguration]

    public init(configurations: [IMAPAccountConfiguration] = []) {
        self.configurations = Dictionary(
            uniqueKeysWithValues: configurations.map { ($0.accountID, $0) }
        )
    }

    public func configuration(for accountID: String) -> IMAPAccountConfiguration? {
        configurations[accountID]
    }

    public func setConfiguration(_ configuration: IMAPAccountConfiguration) {
        configurations[configuration.accountID] = configuration
    }

    public func clearConfiguration(for accountID: String) {
        configurations.removeValue(forKey: accountID)
    }
}

public actor UserDefaultsIMAPAccountConfigurationStore: IMAPAccountConfigurationStore {
    private struct Snapshot: Codable {
        var configurations: [IMAPAccountConfiguration]
    }

    private let userDefaults: UserDefaults
    private let key: String
    private var snapshot: Snapshot

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "app.brev.imap-account-configurations"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot(configurations: [])
        }
    }

    public func configuration(for accountID: String) -> IMAPAccountConfiguration? {
        snapshot.configurations.first { $0.accountID == accountID }
    }

    public func setConfiguration(_ configuration: IMAPAccountConfiguration) {
        if let index = snapshot.configurations.firstIndex(where: {
            $0.accountID == configuration.accountID
        }) {
            snapshot.configurations[index] = configuration
        } else {
            snapshot.configurations.append(configuration)
        }
        persist()
    }

    public func clearConfiguration(for accountID: String) {
        snapshot.configurations.removeAll { $0.accountID == accountID }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: key)
    }
}

public struct MailAccountCredential: Sendable, Hashable, Codable {
    public let incomingUsername: String
    public let outgoingUsername: String
    public let secret: String
    public let authentication: MailServerAuthentication

    public init(
        incomingUsername: String,
        outgoingUsername: String,
        secret: String,
        authentication: MailServerAuthentication
    ) {
        self.incomingUsername = incomingUsername
        self.outgoingUsername = outgoingUsername
        self.secret = secret
        self.authentication = authentication
    }
}

public struct PreparedIMAPAccount: Sendable, Hashable {
    public let account: BrevAccount
    public let configuration: IMAPAccountConfiguration
    public let credential: MailAccountCredential

    public init(
        account: BrevAccount,
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) {
        self.account = account
        self.configuration = configuration
        self.credential = credential
    }
}

public protocol MailCredentialStore: Sendable {
    func credential(for credentialID: String) async -> MailAccountCredential?
    /// Persists a credential, surfacing Keychain/storage failures to the caller.
    func setCredential(
        _ credential: MailAccountCredential,
        for credentialID: String
    ) async throws
    func clearCredential(for credentialID: String) async
    /// Whether the store is temporarily unable to read credentials (e.g. the
    /// system Keychain is locked before first unlock at launch). When true, a
    /// `nil` from `credential(for:)` means "can't read yet", not "no saved
    /// credential", so restore retries instead of forcing re-authentication.
    func isTemporarilyUnavailable() async -> Bool
}

public extension MailCredentialStore {
    func isTemporarilyUnavailable() async -> Bool { false }
}

/// Errors raised while persisting IMAP/SMTP credentials in the system Keychain.
public enum MailCredentialStoreError: Error, LocalizedError, Sendable, Equatable {
    case encodingFailed
    case keychain(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "Couldn't encode the saved mail credential.", bundle: .module)
        case .keychain:
            return String(localized: "Couldn't save the mail credential in Keychain.", bundle: .module)
        }
    }
}

public actor InMemoryMailCredentialStore: MailCredentialStore {
    private var credentials: [String: MailAccountCredential]

    public init(credentials: [String: MailAccountCredential] = [:]) {
        self.credentials = credentials
    }

    public func credential(for credentialID: String) -> MailAccountCredential? {
        credentials[credentialID]
    }

    public func setCredential(
        _ credential: MailAccountCredential,
        for credentialID: String
    ) throws {
        credentials[credentialID] = credential
    }

    public func clearCredential(for credentialID: String) {
        credentials.removeValue(forKey: credentialID)
    }
}

public actor KeychainMailCredentialStore: MailCredentialStore {
    private let service: String

    public init(service: String? = nil) {
        self.service = service
            ?? "\(Bundle.main.bundleIdentifier ?? "app.brev").mail-credentials"
    }

    public func credential(for credentialID: String) -> MailAccountCredential? {
        var query = baseQuery(credentialID: credentialID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(MailAccountCredential.self, from: data)
    }

    public func setCredential(
        _ credential: MailAccountCredential,
        for credentialID: String
    ) throws {
        guard let data = try? JSONEncoder().encode(credential) else {
            throw MailCredentialStoreError.encodingFailed
        }
        let query = baseQuery(credentialID: credentialID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw MailCredentialStoreError.keychain(status: updateStatus)
        }
        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MailCredentialStoreError.keychain(status: addStatus)
        }
    }

    public func clearCredential(for credentialID: String) {
        SecItemDelete(baseQuery(credentialID: credentialID) as CFDictionary)
    }

    /// A `nil` credential while the system Keychain is locked means "can't read
    /// yet", not "no saved credential"; restore uses this to retry rather than
    /// prompt re-authentication (#193).
    public func isTemporarilyUnavailable() -> Bool {
        Self.isSystemKeychainLocked
    }

    /// Returns `true` when `SecItemCopyMatching` reports that the user's
    /// keychain is currently locked (`errSecInteractionNotAllowed`).
    ///
    /// This happens on macOS when the system keychain has not yet been
    /// unlocked after boot (e.g. when "automatic login" is enabled).
    /// The probe issues a benign query that will never match a real item,
    /// so the only result codes are `errSecItemNotFound` (unlocked) or
    /// `errSecInteractionNotAllowed` (locked).
    public static var isSystemKeychainLocked: Bool {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "brev.keychain-lock-probe",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: false
        ]
        return SecItemCopyMatching(probe as CFDictionary, nil) == errSecInteractionNotAllowed
    }

    private func baseQuery(credentialID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID
        ]
    }
}

public enum IMAPAccountProvisioningError: Error, Equatable, LocalizedError, Sendable {
    case invalidEmailAddress
    case invalidCredential
    case missingIncomingServer
    case missingOutgoingServer
    case invalidIncomingServer
    case invalidOutgoingServer
    case unsupportedAuthentication(MailServerAuthentication)
    case credentialStorageUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidEmailAddress:
            String(localized: "Enter a valid email address.", bundle: .module)
        case .invalidCredential:
            String(localized: "Mail account credentials contain an invalid character.", bundle: .module)
        case .missingIncomingServer:
            String(localized: "IMAP server settings are missing.", bundle: .module)
        case .missingOutgoingServer:
            String(localized: "SMTP server settings are missing.", bundle: .module)
        case .invalidIncomingServer:
            String(localized: "IMAP server settings are invalid.", bundle: .module)
        case .invalidOutgoingServer:
            String(localized: "SMTP server settings are invalid.", bundle: .module)
        case .unsupportedAuthentication(let authentication):
            String(localized: "Brev cannot add \(authentication.rawValue) mail accounts yet.", bundle: .module)
        case .credentialStorageUnavailable:
            String(
                localized: "Couldn't save the account password in Keychain. Test connection can work without saving; Add account needs local credential storage.",
                bundle: .module
            )
        }
    }
}

public struct IMAPAccountProvisioner: Sendable {
    private let accountStore: any AccountStore
    private let configurationStore: any IMAPAccountConfigurationStore
    private let credentialStore: any MailCredentialStore

    public init(
        accountStore: any AccountStore,
        configurationStore: any IMAPAccountConfigurationStore,
        credentialStore: any MailCredentialStore
    ) {
        self.accountStore = accountStore
        self.configurationStore = configurationStore
        self.credentialStore = credentialStore
    }

    @discardableResult
    public func addAccount(
        emailAddress: String,
        displayName: String?,
        discovery: MailAccountDiscoveryResult,
        password: String
    ) async throws -> BrevAccount {
        let prepared = try prepareAccount(
            emailAddress: emailAddress,
            displayName: displayName,
            discovery: discovery,
            password: password
        )

        await configurationStore.setConfiguration(prepared.configuration)
        do {
            try await credentialStore.setCredential(
                prepared.credential,
                for: prepared.configuration.credentialID
            )
        } catch {
            await configurationStore.clearConfiguration(for: prepared.account.id)
            throw error
        }
        guard await credentialStore.credential(for: prepared.configuration.credentialID)
            == prepared.credential
        else {
            await credentialStore.clearCredential(for: prepared.configuration.credentialID)
            await configurationStore.clearConfiguration(for: prepared.account.id)
            throw IMAPAccountProvisioningError.credentialStorageUnavailable
        }
        await accountStore.add(prepared.account)
        await accountStore.setCurrent(prepared.account.id)
        return prepared.account
    }

    public func prepareAccount(
        emailAddress: String,
        displayName: String?,
        discovery: MailAccountDiscoveryResult,
        password: String
    ) throws -> PreparedIMAPAccount {
        let normalizedEmailAddress = try Self.normalizedEmailAddress(emailAddress)
        let credentialEmailAddress = try Self.credentialEmailAddress(emailAddress)
        try Self.validateCredentialSecret(password)
        guard let incoming = discovery.incoming else {
            throw IMAPAccountProvisioningError.missingIncomingServer
        }
        guard let outgoing = discovery.outgoing else {
            throw IMAPAccountProvisioningError.missingOutgoingServer
        }
        guard Self.isValidServer(incoming, kind: .imap) else {
            throw IMAPAccountProvisioningError.invalidIncomingServer
        }
        guard Self.isValidServer(outgoing, kind: .smtp) else {
            throw IMAPAccountProvisioningError.invalidOutgoingServer
        }
        let canonicalManageSieve: MailServerSettings?
        if let manageSieve = discovery.manageSieve {
            // Accept `.imap` from older persisted/discovery values, then
            // canonicalize it to the explicit ManageSieve endpoint kind.
            guard manageSieve.kind == .manageSieve || manageSieve.kind == .imap,
                  MailAccountAutodiscovery.isValidServerHost(manageSieve.host),
                  manageSieve.port > 0 else {
                throw IMAPAccountProvisioningError.invalidIncomingServer
            }
            canonicalManageSieve = Self.canonicalManageSieveSettings(manageSieve)
        } else {
            canonicalManageSieve = nil
        }
        let canonicalIncoming = Self.canonicalServerSettings(incoming)
        let canonicalOutgoing = Self.canonicalServerSettings(outgoing)

        let authentication = try Self.credentialAuthentication(
            incoming: canonicalIncoming,
            outgoing: canonicalOutgoing
        )
        let accountID = BrevAccount.imapSMTPAccountID(forEmailAddress: normalizedEmailAddress)
        let normalizedDisplayName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let accountDisplayName = normalizedDisplayName?.isEmpty == false
            ? normalizedDisplayName!
            : normalizedEmailAddress
        let account = BrevAccount(
            id: accountID,
            displayName: accountDisplayName,
            emailAddress: normalizedEmailAddress
        )
        let configuration = IMAPAccountConfiguration(
            accountID: accountID,
            emailAddress: credentialEmailAddress,
            displayName: accountDisplayName,
            incoming: canonicalIncoming,
            outgoing: canonicalOutgoing,
            manageSieve: canonicalManageSieve,
            credentialID: accountID
        )
        let incomingUsername = canonicalIncoming.resolvedUsername(for: credentialEmailAddress)
        let outgoingUsername = canonicalOutgoing.resolvedUsername(for: credentialEmailAddress)
        try Self.validateResolvedUsername(incomingUsername)
        try Self.validateResolvedUsername(outgoingUsername)
        let credential = MailAccountCredential(
            incomingUsername: incomingUsername,
            outgoingUsername: outgoingUsername,
            secret: password,
            authentication: authentication
        )
        return PreparedIMAPAccount(
            account: account,
            configuration: configuration,
            credential: credential
        )
    }

    /// Provision an IMAP/SMTP account authenticated via OAuth2 (XOAUTH2).
    ///
    /// Unlike `addAccount(emailAddress:displayName:discovery:password:)`, this
    /// path accepts a short-lived bearer token and stores it with `.xoauth2`
    /// authentication. Server settings must already include `.xoauth2` as their
    /// `authentication` value.
    @discardableResult
    public func addOAuthAccount(
        emailAddress: String,
        displayName: String?,
        incoming: MailServerSettings,
        outgoing: MailServerSettings,
        accessToken: String
    ) async throws -> BrevAccount {
        let normalizedEmailAddress = try Self.normalizedEmailAddress(emailAddress)
        let credentialEmailAddress = try Self.credentialEmailAddress(emailAddress)
        try Self.validateCredentialSecret(accessToken)
        guard Self.isValidServer(incoming, kind: .imap) else {
            throw IMAPAccountProvisioningError.invalidIncomingServer
        }
        guard Self.isValidServer(outgoing, kind: .smtp) else {
            throw IMAPAccountProvisioningError.invalidOutgoingServer
        }
        let canonicalIncoming = Self.canonicalServerSettings(incoming)
        let canonicalOutgoing = Self.canonicalServerSettings(outgoing)
        let accountID = BrevAccount.imapSMTPAccountID(forEmailAddress: normalizedEmailAddress)
        let normalizedDisplayName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let accountDisplayName = normalizedDisplayName?.isEmpty == false
            ? normalizedDisplayName!
            : normalizedEmailAddress
        let account = BrevAccount(
            id: accountID,
            displayName: accountDisplayName,
            emailAddress: normalizedEmailAddress
        )
        let configuration = IMAPAccountConfiguration(
            accountID: accountID,
            emailAddress: credentialEmailAddress,
            displayName: accountDisplayName,
            incoming: canonicalIncoming,
            outgoing: canonicalOutgoing,
            credentialID: accountID
        )
        let incomingUsername = canonicalIncoming.resolvedUsername(for: credentialEmailAddress)
        let outgoingUsername = canonicalOutgoing.resolvedUsername(for: credentialEmailAddress)
        try Self.validateResolvedUsername(incomingUsername)
        try Self.validateResolvedUsername(outgoingUsername)
        let credential = MailAccountCredential(
            incomingUsername: incomingUsername,
            outgoingUsername: outgoingUsername,
            secret: accessToken,
            authentication: .xoauth2
        )
        await configurationStore.setConfiguration(configuration)
        do {
            try await credentialStore.setCredential(credential, for: accountID)
        } catch {
            await configurationStore.clearConfiguration(for: accountID)
            throw error
        }
        guard await credentialStore.credential(for: accountID) == credential else {
            await credentialStore.clearCredential(for: accountID)
            await configurationStore.clearConfiguration(for: accountID)
            throw IMAPAccountProvisioningError.credentialStorageUnavailable
        }
        await accountStore.add(account)
        await accountStore.setCurrent(accountID)
        return account
    }

    public func removeAccount(_ accountID: String) async {
        let credentialID = await configurationStore.configuration(for: accountID)?
            .credentialID ?? accountID
        await credentialStore.clearCredential(for: credentialID)
        await configurationStore.clearConfiguration(for: accountID)
        await accountStore.remove(accountID)
        // Clear the persisted IDLE-unsupported flag so a re-added account
        // can attempt IDLE again with a clean slate.
        UserDefaults.standard.removeObject(
            forKey: "brev.imap.idle-unsupported.\(accountID)"
        )
        // Drop any scheduled sends for the account so they can't fire (or be
        // reconciled on next launch) after the account is gone (#167).
        ScheduledSendStore.purge(accountID: accountID)
        // Drop the sent-message ledger too so a removed account leaves no
        // orphaned `sentMessageLedger.<accountID>` key behind (#14).
        SentMessageLedger.purge(accountID: accountID)
    }

    private static func normalizedEmailAddress(_ emailAddress: String) throws -> String {
        let normalized = emailAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard MailAccountAutodiscovery.isValidEmailAddress(normalized) else {
            throw IMAPAccountProvisioningError.invalidEmailAddress
        }
        return normalized
    }

    private static func credentialEmailAddress(_ emailAddress: String) throws -> String {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MailAccountAutodiscovery.isValidEmailAddress(trimmed) else {
            throw IMAPAccountProvisioningError.invalidEmailAddress
        }

        let parts = trimmed.split(
            separator: "@",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard parts.count == 2,
              !parts[0].isEmpty
        else {
            throw IMAPAccountProvisioningError.invalidEmailAddress
        }
        let domain = String(parts[1])
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return "\(parts[0])@\(domain)"
    }

    private static func validateCredentialSecret(_ secret: String) throws {
        guard !secret.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw IMAPAccountProvisioningError.invalidCredential
        }
    }

    private static func validateResolvedUsername(_ username: String) throws {
        guard !username.isEmpty,
              !username.unicodeScalars.contains(where: { scalar in
                  scalar.value == 0
                      || CharacterSet.newlines.contains(scalar)
              })
        else {
            throw IMAPAccountProvisioningError.invalidCredential
        }
    }

    private static func isValidServer(
        _ server: MailServerSettings,
        kind: MailServerProtocolKind
    ) -> Bool {
        return server.kind == kind
            && MailAccountAutodiscovery.isValidServerHost(server.host)
            && server.port > 0
    }

    private static func canonicalServerSettings(
        _ server: MailServerSettings
    ) -> MailServerSettings {
        var canonical = server
        canonical.host = server.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return canonical
    }

    private static func canonicalManageSieveSettings(
        _ server: MailServerSettings
    ) -> MailServerSettings {
        MailServerSettings(
            kind: .manageSieve,
            host: server.host
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased(),
            port: server.port,
            tlsMode: server.tlsMode,
            authentication: server.authentication,
            usernameTemplate: server.usernameTemplate
        )
    }

    private static func credentialAuthentication(
        incoming: MailServerSettings,
        outgoing: MailServerSettings
    ) throws -> MailServerAuthentication {
        let authentications = [incoming.authentication, outgoing.authentication]
        if let unsupported = authentications.first(where: { authentication in
            switch authentication {
            case .xoauth2, .encryptedPassword, .none:
                return true
            case .password, .appPassword:
                return false
            }
        }) {
            throw IMAPAccountProvisioningError.unsupportedAuthentication(unsupported)
        }
        if incoming.authentication == .appPassword || outgoing.authentication == .appPassword {
            return .appPassword
        }
        return incoming.authentication
    }
}

public struct IMAPAccountConnector: Sendable {
    public struct ConnectedAccount: Sendable {
        public let account: BrevAccount
        public let backend: IMAPSMTPBackend

        public init(account: BrevAccount, backend: IMAPSMTPBackend) {
            self.account = account
            self.backend = backend
        }
    }

    private struct RollbackSnapshot: Sendable {
        let accountID: BrevAccount.ID
        let existingAccount: BrevAccount?
        let previousCurrentAccountID: BrevAccount.ID?
        let configuration: IMAPAccountConfiguration?
        let credential: MailAccountCredential?
    }

    public typealias OutgoingServerValidationOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential) async throws
            -> Void
    public typealias OAuthRefreshOperation =
        @Sendable (BrevAccount.ID, IMAPAccountConfiguration, any TokenStore) async throws
            -> Token
    public typealias LocalSearchIndexFactory =
        @Sendable (BrevAccount.ID) -> (any MailLocalSearchIndex)?

    private let provisioner: IMAPAccountProvisioner
    private let accountStore: any AccountStore
    private let configurationStore: any IMAPAccountConfigurationStore
    private let credentialStore: any MailCredentialStore
    private let listFolders: IMAPSMTPBackend.FolderListingOperation
    private let validateOutgoingServer: OutgoingServerValidationOperation?
    private let createFolder: IMAPSMTPBackend.FolderCreateOperation?
    private let renameFolder: IMAPSMTPBackend.FolderRenameOperation?
    private let deleteFolder: IMAPSMTPBackend.FolderDeleteOperation?
    private let listMessages: IMAPSMTPBackend.MessageListingOperation?
    private let searchMessages: IMAPSMTPBackend.MessageSearchOperation?
    private let searchMessagePage: IMAPSMTPBackend.MessageSearchPageOperation?
    private let fetchMessageSource: IMAPSMTPBackend.MessageSourceFetchOperation?
    private let fetchMessageBody: IMAPSMTPBackend.MessageBodyFetchOperation?
    private let fetchMessagePart: IMAPSMTPBackend.MessagePartFetchOperation?
    private let setMessageFlag: IMAPSMTPBackend.MessageFlagOperation?
    private let setMessageKeyword: IMAPSMTPBackend.MessageKeywordOperation?
    private let setMessageLabels: IMAPSMTPBackend.MessageLabelOperation?
    private let moveMessages: IMAPSMTPBackend.MessageMoveOperation?
    private let copyMessages: IMAPSMTPBackend.MessageCopyOperation?
    private let permanentlyDeleteMessages: IMAPSMTPBackend.MessagePermanentDeleteOperation?
    private let sendMessage: IMAPSMTPBackend.MessageSendOperation?
    private let appendSentMessage: IMAPSMTPBackend.MessageAppendOperation?
    private let appendDraftMessage: IMAPSMTPBackend.DraftAppendOperation?
    private let idleEvents: IMAPSMTPBackend.IdleEventOperation?
    private let condstoreSync: IMAPSMTPBackend.CONDSTORESyncOperation?
    private let manageSieveRuleSync: IMAPSMTPBackend.ManageSieveRuleSyncOperation?
    private let disconnectSession: IMAPSMTPBackend.SessionDisconnectOperation?
    private let folderCache: (any IMAPFolderSnapshotCache)?
    private let headerCache: (any IMAPMailboxHeaderCache)?
    private let sourceCache: (any IMAPMessageSourceCache)?
    private let bodyCache: (any IMAPMessageBodyCache)?
    private let localSearchIndex: LocalSearchIndexFactory?
    private let draftStagingStore: (any IMAPDraftStagingStore)?
    private let offlineMutationQueue: (@Sendable (BrevAccount.ID) -> (any OfflineMutationQueue))?
    private let offlineMutationConflictStore: (@Sendable (BrevAccount.ID) -> (any OfflineMutationConflictStore))?
    /// Used to refresh XOAUTH2 tokens on reconnect. Nil means no automatic refresh.
    private let tokenStore: (any TokenStore)?
    private let refreshOAuthToken: OAuthRefreshOperation?
    /// Coalesces concurrent refreshes from reconnect and SMTP retry paths.
    private let oauthRefreshCoordinator: OAuthRefreshCoordinator
    /// Outbound signing/encryption engine (ADR-0021). Nil disables E2EE send,
    /// in which case a draft requesting security fails closed in the backend.
    private let outboundMessagePreparer: (any OutboundMessagePreparing)?

    public init(
        accountStore: any AccountStore,
        configurationStore: any IMAPAccountConfigurationStore,
        credentialStore: any MailCredentialStore,
        listFolders: @escaping IMAPSMTPBackend.FolderListingOperation,
        validateOutgoingServer: OutgoingServerValidationOperation? = nil,
        createFolder: IMAPSMTPBackend.FolderCreateOperation? = nil,
        renameFolder: IMAPSMTPBackend.FolderRenameOperation? = nil,
        deleteFolder: IMAPSMTPBackend.FolderDeleteOperation? = nil,
        listMessages: IMAPSMTPBackend.MessageListingOperation? = nil,
        searchMessages: IMAPSMTPBackend.MessageSearchOperation? = nil,
        searchMessagePage: IMAPSMTPBackend.MessageSearchPageOperation? = nil,
        fetchMessageSource: IMAPSMTPBackend.MessageSourceFetchOperation? = nil,
        fetchMessageBody: IMAPSMTPBackend.MessageBodyFetchOperation? = nil,
        fetchMessagePart: IMAPSMTPBackend.MessagePartFetchOperation? = nil,
        setMessageFlag: IMAPSMTPBackend.MessageFlagOperation? = nil,
        setMessageKeyword: IMAPSMTPBackend.MessageKeywordOperation? = nil,
        setMessageLabels: IMAPSMTPBackend.MessageLabelOperation? = nil,
        moveMessages: IMAPSMTPBackend.MessageMoveOperation? = nil,
        copyMessages: IMAPSMTPBackend.MessageCopyOperation? = nil,
        permanentlyDeleteMessages: IMAPSMTPBackend.MessagePermanentDeleteOperation? = nil,
        sendMessage: IMAPSMTPBackend.MessageSendOperation? = nil,
        appendSentMessage: IMAPSMTPBackend.MessageAppendOperation? = nil,
        appendDraftMessage: IMAPSMTPBackend.DraftAppendOperation? = nil,
        idleEvents: IMAPSMTPBackend.IdleEventOperation? = nil,
        condstoreSync: IMAPSMTPBackend.CONDSTORESyncOperation? = nil,
        manageSieveRuleSync: IMAPSMTPBackend.ManageSieveRuleSyncOperation? = nil,
        disconnectSession: IMAPSMTPBackend.SessionDisconnectOperation? = nil,
        folderCache: (any IMAPFolderSnapshotCache)? = nil,
        headerCache: (any IMAPMailboxHeaderCache)? = nil,
        sourceCache: (any IMAPMessageSourceCache)? = nil,
        bodyCache: (any IMAPMessageBodyCache)? = nil,
        localSearchIndex: LocalSearchIndexFactory? = nil,
        draftStagingStore: (any IMAPDraftStagingStore)? = nil,
        offlineMutationQueue: (@Sendable (BrevAccount.ID) -> (any OfflineMutationQueue))? = nil,
        offlineMutationConflictStore: (@Sendable (BrevAccount.ID) -> (any OfflineMutationConflictStore))? = nil,
        tokenStore: (any TokenStore)? = nil,
        refreshOAuthToken: OAuthRefreshOperation? = nil,
        oauthRefreshCoordinator: OAuthRefreshCoordinator = OAuthRefreshCoordinator(),
        outboundMessagePreparer: (any OutboundMessagePreparing)? = nil
    ) {
        provisioner = IMAPAccountProvisioner(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore
        )
        self.accountStore = accountStore
        self.configurationStore = configurationStore
        self.credentialStore = credentialStore
        self.listFolders = listFolders
        self.validateOutgoingServer = validateOutgoingServer
        self.createFolder = createFolder
        self.renameFolder = renameFolder
        self.deleteFolder = deleteFolder
        self.listMessages = listMessages
        self.searchMessages = searchMessages
        self.searchMessagePage = searchMessagePage
        self.fetchMessageSource = fetchMessageSource
        self.fetchMessageBody = fetchMessageBody
        self.fetchMessagePart = fetchMessagePart
        self.setMessageFlag = setMessageFlag
        self.setMessageKeyword = setMessageKeyword
        self.setMessageLabels = setMessageLabels
        self.moveMessages = moveMessages
        self.copyMessages = copyMessages
        self.permanentlyDeleteMessages = permanentlyDeleteMessages
        self.sendMessage = sendMessage
        self.appendSentMessage = appendSentMessage
        self.appendDraftMessage = appendDraftMessage
        self.idleEvents = idleEvents
        self.condstoreSync = condstoreSync
        self.manageSieveRuleSync = manageSieveRuleSync
        self.disconnectSession = disconnectSession
        self.folderCache = folderCache
        self.headerCache = headerCache
        self.sourceCache = sourceCache
        self.bodyCache = bodyCache
        self.localSearchIndex = localSearchIndex
        self.draftStagingStore = draftStagingStore
        self.offlineMutationQueue = offlineMutationQueue
        self.offlineMutationConflictStore = offlineMutationConflictStore
        self.tokenStore = tokenStore
        self.refreshOAuthToken = refreshOAuthToken
        self.oauthRefreshCoordinator = oauthRefreshCoordinator
        self.outboundMessagePreparer = outboundMessagePreparer
    }

    public func provisionAndConnect(
        _ request: IMAPAccountSetupRequest
    ) async throws -> ConnectedAccount {
        let snapshot = await rollbackSnapshot(forEmailAddress: request.emailAddress)
        do {
            let account = try await provisioner.addAccount(
                emailAddress: request.emailAddress,
                displayName: request.displayName,
                discovery: request.discovery,
                password: request.password
            )
            if snapshot.existingAccount == nil {
                await clearLocalStores(accountID: account.id)
            }
            guard let validatedBackend = try await restore(
                account,
                includeLocalStores: snapshot.existingAccount == nil
            ) else {
                throw MailBackendError.notFound(id: account.id)
            }
            try await validateOutgoingServerIfNeeded(accountID: account.id)
            if snapshot.existingAccount != nil {
                await clearLocalStores(accountID: account.id)
                guard let backend = try await restore(account) else {
                    throw MailBackendError.notFound(id: account.id)
                }
                return ConnectedAccount(account: account, backend: backend)
            }
            return ConnectedAccount(account: account, backend: validatedBackend)
        } catch {
            await rollbackProvisioning(snapshot)
            throw error
        }
    }

    public func validate(_ request: IMAPAccountSetupRequest) async throws {
        let prepared = try provisioner.prepareAccount(
            emailAddress: request.emailAddress,
            displayName: request.displayName,
            discovery: request.discovery,
            password: request.password
        )
        let backend = makeBackend(
            account: prepared.account,
            configuration: prepared.configuration,
            credential: prepared.credential,
            includeLocalStores: false
        )
        // Validate the session only — no poller, no remote-draft load, and no
        // delivery pass, so a "Test connection" can never send scheduled mail.
        // Tear down on every path (including the outgoing-server throw) so the
        // throwaway backend doesn't leave a session open against capped servers.
        do {
            try await backend.connect()
            try await validateOutgoingServer?(
                prepared.configuration,
                prepared.credential
            )
            await backend.disconnect()
        } catch {
            await backend.disconnect()
            throw error
        }
    }

    /// Provision and connect an OAuth2-authenticated IMAP/SMTP account.
    ///
    /// Mirrors `provisionAndConnect(_:)` but accepts a `IMAPOAuthSetupRequest`
    /// carrying a bearer token from a completed OAuth2 flow. The caller is
    /// responsible for obtaining the token via `GoogleOAuthFlow` or equivalent
    /// before invoking this method.
    public func provisionAndConnectOAuth(
        _ request: IMAPOAuthSetupRequest
    ) async throws -> ConnectedAccount {
        let snapshot = await rollbackSnapshot(forEmailAddress: request.emailAddress)
        do {
            let account = try await provisioner.addOAuthAccount(
                emailAddress: request.emailAddress,
                displayName: request.displayName,
                incoming: request.incoming,
                outgoing: request.outgoing,
                accessToken: request.accessToken
            )
            if snapshot.existingAccount == nil {
                await clearLocalStores(accountID: account.id)
            }
            guard let validatedBackend = try await restore(
                account,
                includeLocalStores: snapshot.existingAccount == nil
            ) else {
                throw MailBackendError.notFound(id: account.id)
            }
            try await validateOutgoingServerIfNeeded(accountID: account.id)
            if snapshot.existingAccount != nil {
                await clearLocalStores(accountID: account.id)
                guard let backend = try await restore(account) else {
                    throw MailBackendError.notFound(id: account.id)
                }
                return ConnectedAccount(account: account, backend: backend)
            }
            return ConnectedAccount(account: account, backend: validatedBackend)
        } catch {
            await rollbackProvisioning(snapshot)
            throw error
        }
    }

    public func restore(
        _ account: BrevAccount,
        includeLocalStores: Bool = true
    ) async throws -> IMAPSMTPBackend? {
        let startedAt = Date()
        guard account.backendIdentifier == BrevAccount.imapSMTPBackendIdentifier else {
            return nil
        }
        guard let configuration = await configurationStore.configuration(
            for: account.id
        ) else {
            return nil
        }
        guard let credential = await credentialStore.credential(
            for: configuration.credentialID
        ) else {
            // A locked Keychain reads back as a nil credential even though the
            // saved sign-in still exists. Signal a retryable transient state
            // instead of prompting the user to sign in again (#193 symptom 2).
            if await credentialStore.isTemporarilyUnavailable() {
                throw MailBackendError.credentialStoreUnavailable
            }
            throw MailBackendError.authenticationRequired
        }

        let backend = makeBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            includeLocalStores: includeLocalStores
        )
        if await backend.restoreCachedFoldersForStartup() {
            MailPerformanceDiagnostics.logStartupRestore(
                path: .cache,
                durationMilliseconds: MailPerformanceDiagnostics.durationMilliseconds(since: startedAt)
            )
            backend.trackBackgroundWork { [self, backend] in
                // Yield once so the cache-restored backend is returned to the
                // session/UI before remote reconciliation can update health.
                await Task.yield()
                await reconnectCachedStartupBackend(backend)
            }
            return backend
        }
        try await backend.connect()
        Task {
            await backend.replayOfflineMutations(processSends: false)
        }
        MailPerformanceDiagnostics.logStartupRestore(
            path: .remote,
            durationMilliseconds: MailPerformanceDiagnostics.durationMilliseconds(since: startedAt)
        )
        return backend
    }

    /// Reconciles a cache-restored mailbox without keeping session restoration
    /// on the remote IMAP LIST critical path. OAuth refresh follows the same
    /// recovery path as a foreground restore.
    private func reconnectCachedStartupBackend(
        _ backend: IMAPSMTPBackend
    ) async {
        do {
            try await backend.connect()
        } catch {
            return
        }
        await backend.replayOfflineMutations(processSends: false)
    }

    private func makeBackend(
        account: BrevAccount,
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        includeLocalStores: Bool
    ) -> IMAPSMTPBackend {
        let refreshOAuthCredential: IMAPSMTPBackend.OAuthCredentialRefreshOperation?
        if let tokenStore {
            let refreshOAuthToken = refreshOAuthToken
            let credentialStore = credentialStore
            refreshOAuthCredential = { accountID, configuration, credential in
                let newToken: Token
                if let refreshOAuthToken {
                    newToken = try await oauthRefreshCoordinator.run(for: accountID) {
                        let token = try await refreshOAuthToken(accountID, configuration, tokenStore)
                        try await tokenStore.setToken(token, for: accountID)
                        return token
                    }
                } else {
                    let refresher = Self.oauthRefresher(
                        forIMAPHost: configuration.incoming.host,
                        tokenStore: tokenStore,
                        coordinator: oauthRefreshCoordinator
                    )
                    newToken = try await refresher.refresh(for: accountID)
                }
                let updated = MailAccountCredential(
                    incomingUsername: credential.incomingUsername,
                    outgoingUsername: credential.outgoingUsername,
                    secret: newToken.accessToken,
                    authentication: .xoauth2
                )
                try await credentialStore.setCredential(
                    updated,
                    for: configuration.credentialID
                )
                return updated
            }
        } else {
            refreshOAuthCredential = nil
        }

        return IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: listFolders,
            createFolder: createFolder,
            renameFolder: renameFolder,
            deleteFolder: deleteFolder,
            listMessages: listMessages,
            searchMessages: searchMessages,
            searchMessagePage: searchMessagePage,
            fetchMessageSource: fetchMessageSource,
            fetchMessageBody: fetchMessageBody,
            fetchMessagePart: fetchMessagePart,
            setMessageFlag: setMessageFlag,
            setMessageKeyword: setMessageKeyword,
            setMessageLabels: setMessageLabels,
            moveMessages: moveMessages,
            copyMessages: copyMessages,
            permanentlyDeleteMessages: permanentlyDeleteMessages,
            sendMessage: sendMessage,
            refreshOAuthCredential: refreshOAuthCredential,
            appendSentMessage: appendSentMessage,
            appendDraftMessage: appendDraftMessage,
            idleEvents: idleEvents,
            condstoreSync: condstoreSync,
            manageSieveRuleSync: manageSieveRuleSync,
            disconnectSession: disconnectSession,
            folderCache: includeLocalStores ? folderCache : nil,
            headerCache: includeLocalStores ? headerCache : nil,
            sourceCache: includeLocalStores ? sourceCache : nil,
            bodyCache: includeLocalStores ? bodyCache : nil,
            localSearchIndex: includeLocalStores ? localSearchIndex?(account.id) : nil,
            draftStagingStore: includeLocalStores ? draftStagingStore : nil,
            offlineMutationQueue: offlineMutationQueue?(account.id),
            offlineMutationConflictStore: offlineMutationConflictStore?(account.id),
            outboundMessagePreparer: outboundMessagePreparer,
            sentMessageLedger: SentMessageLedger()
        )
    }

    private static func oauthRefresher(
        forIMAPHost host: String,
        tokenStore: any TokenStore,
        coordinator: OAuthRefreshCoordinator
    ) -> OAuthTokenRefresher {
        let lowercased = host.lowercased()
        if lowercased.hasSuffix(".microsoft.com") || lowercased.hasSuffix(".office365.com")
            || lowercased == "outlook.office365.com" {
            return .outlook(tokenStore: tokenStore, coordinator: coordinator)
        }
        return OAuthTokenRefresher(tokenStore: tokenStore, coordinator: coordinator)
    }

    public func removeAccount(_ accountID: String) async {
        await provisioner.removeAccount(accountID)
        await clearLocalStores(accountID: accountID)
    }

    private func clearLocalStores(accountID: String) async {
        await folderCache?.clear(accountID: accountID)
        await headerCache?.clear(accountID: accountID)
        await sourceCache?.clear(accountID: accountID)
        await draftStagingStore?.clear(accountID: accountID)
        try? await offlineMutationQueue?(accountID).removeAll()
        try? await offlineMutationConflictStore?(accountID).removeAll()
    }

    private func validateOutgoingServerIfNeeded(
        accountID: BrevAccount.ID
    ) async throws {
        guard let validateOutgoingServer else { return }
        guard let configuration = await configurationStore.configuration(
            for: accountID
        ) else {
            throw MailBackendError.notFound(id: accountID)
        }
        guard let credential = await credentialStore.credential(
            for: configuration.credentialID
        ) else {
            throw MailBackendError.authenticationRequired
        }
        try await validateOutgoingServer(configuration, credential)
    }

    private func rollbackSnapshot(
        forEmailAddress emailAddress: String
    ) async -> RollbackSnapshot {
        let accountID = BrevAccount.imapSMTPAccountID(forEmailAddress: emailAddress)
        let existingAccount = await accountStore.accounts.first { $0.id == accountID }
        let previousCurrentAccountID = await accountStore.current?.id
        let configuration = await configurationStore.configuration(for: accountID)
        let credential: MailAccountCredential?
        if let configuration {
            credential = await credentialStore.credential(for: configuration.credentialID)
        } else {
            credential = nil
        }
        return RollbackSnapshot(
            accountID: accountID,
            existingAccount: existingAccount,
            previousCurrentAccountID: previousCurrentAccountID,
            configuration: configuration,
            credential: credential
        )
    }

    private func rollbackProvisioning(_ snapshot: RollbackSnapshot) async {
        if let existingAccount = snapshot.existingAccount {
            if let configuration = snapshot.configuration {
                await configurationStore.setConfiguration(configuration)
                if let credential = snapshot.credential {
                    try? await credentialStore.setCredential(
                        credential,
                        for: configuration.credentialID
                    )
                }
            } else {
                await configurationStore.clearConfiguration(for: snapshot.accountID)
                await credentialStore.clearCredential(for: snapshot.accountID)
            }
            await accountStore.add(existingAccount)
            if let previousCurrentAccountID = snapshot.previousCurrentAccountID {
                await accountStore.setCurrent(previousCurrentAccountID)
            }
        } else {
            await removeAccount(snapshot.accountID)
        }
    }
}
