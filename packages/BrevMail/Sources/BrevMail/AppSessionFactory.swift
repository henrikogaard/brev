/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import AuthenticationServices
import BrevAI
import BrevBackend
import BrevCalendar
import BrevSettings
import Foundation

/// Errors raised when app-factory wiring cannot safely remove a provider account.
public enum AppSessionFactoryError: Error, Sendable, Equatable, LocalizedError {
    /// Native Gmail cleanup is unavailable, so account state must be retained.
    case missingGoogleOAuthRemovalCoordinator

    /// Safe user-facing error text.
    public var errorDescription: String? {
        switch self {
        case .missingGoogleOAuthRemovalCoordinator:
            return String(
                localized: "Brev cannot remove this Gmail account yet. Try again after Gmail cleanup is available.",
                bundle: .module
            )
        }
    }
}

/// Builds the app-level session shared by the macOS and iOS targets.
public enum AppSessionFactory {
    /// Platform-owned values needed to finish the shared session bootstrap.
    public struct Configuration {
        public let applicationSupportURL: URL
        public let oauthPresentationAnchor: @MainActor () throws -> ASPresentationAnchor
        public let localSearchIndex: IMAPAccountConnector.LocalSearchIndexFactory?
        public let isDemoModeRequested: @MainActor () -> Bool
        public let makeDemoBackend: @MainActor () -> any MailBackend
        /// Optional provider connector for native Google API accounts. When
        /// absent, Google OAuth continues through the IMAP/SMTP fallback.
        public let googleOAuthAccountProvisioningCoordinator:
            AppSession.GoogleOAuthAccountProvisioningCoordinator?
        /// Restores a native Google backend for a stored Gmail API account.
        public let googleOAuthRestoreCoordinator:
            (@MainActor (BrevAccount) async throws -> AppSession.LoginResult?)?
        /// Clears native Google account state during sign-out/removal.
        public let googleOAuthRemovalCoordinator:
            (@MainActor (BrevAccount.ID) async throws -> Void)?
        /// Enables a PIM feature on a Google account through fresh
        /// authorization (ADR-0072). Absent, Google enablement is
        /// unavailable and the settings row stays inert.
        public let googlePIMEnablementCoordinator:
            AppSession.GooglePIMEnablementCoordinator?
        /// Resolves a Google access token for a linked account so PIM
        /// collection discovery can ride the shared grant (ADR-0072).
        /// Absent, Google collection refresh reports unavailable.
        public let googlePIMAccessTokenProvider:
            (@Sendable (BrevAccount.ID) async throws -> String)?
        /// Creates the durable local-mail backend (ADR-0077). Defaults to a
        /// Maildir store under `applicationSupportURL/LocalFolders`; tests can
        /// inject a temporary root.
        public let localBackendFactory: (@Sendable () -> LocalMailBackend)?

        /// Creates the platform dependencies for the shared session factory.
        ///
        /// - Parameters:
        ///   - applicationSupportURL: The app-specific support directory.
        ///   - oauthPresentationAnchor: Resolves the active platform window for OAuth.
        ///   - localSearchIndex: Creates the optional app-owned local search index.
        ///   - isDemoModeRequested: Reports whether developer demo mode is enabled.
        ///   - makeDemoBackend: Creates a fresh demo backend for sign-in affordances.
        ///   - googleOAuthAccountProvisioningCoordinator: Provisions a verified
        ///     Google OAuth result through a native provider backend when one is
        ///     available.
        ///   - googleOAuthRestoreCoordinator: Restores stored Gmail API accounts.
        ///   - googleOAuthRemovalCoordinator: Removes stored Gmail API account state.
        ///   - googlePIMEnablementCoordinator: Authorizes and installs a PIM
        ///     feature grant on a Google account (ADR-0072).
        ///   - googlePIMAccessTokenProvider: Resolves the account's Google
        ///     access token for PIM collection discovery.
        public init(
            applicationSupportURL: URL,
            oauthPresentationAnchor: @escaping @MainActor () throws -> ASPresentationAnchor,
            localSearchIndex: IMAPAccountConnector.LocalSearchIndexFactory? = nil,
            isDemoModeRequested: @escaping @MainActor () -> Bool = {
                #if DEBUG
                DeveloperSettings.isDemoModeRequested(isDeveloperBuild: true)
                #else
                false
                #endif
            },
            makeDemoBackend: @escaping @MainActor () -> any MailBackend = { MockBackend() },
            googleOAuthAccountProvisioningCoordinator:
            AppSession.GoogleOAuthAccountProvisioningCoordinator? = nil,
            googleOAuthRestoreCoordinator:
            (@MainActor (BrevAccount) async throws -> AppSession.LoginResult?)? = nil,
            googleOAuthRemovalCoordinator:
            (@MainActor (BrevAccount.ID) async throws -> Void)? = nil,
            googlePIMEnablementCoordinator:
            AppSession.GooglePIMEnablementCoordinator? = nil,
            googlePIMAccessTokenProvider:
            (@Sendable (BrevAccount.ID) async throws -> String)? = nil,
            localBackendFactory: (@Sendable () -> LocalMailBackend)? = nil
        ) {
            self.applicationSupportURL = applicationSupportURL
            self.oauthPresentationAnchor = oauthPresentationAnchor
            self.localSearchIndex = localSearchIndex
            self.isDemoModeRequested = isDemoModeRequested
            self.makeDemoBackend = makeDemoBackend
            self.googleOAuthAccountProvisioningCoordinator =
                googleOAuthAccountProvisioningCoordinator
            self.googleOAuthRestoreCoordinator = googleOAuthRestoreCoordinator
            self.googleOAuthRemovalCoordinator = googleOAuthRemovalCoordinator
            self.googlePIMEnablementCoordinator = googlePIMEnablementCoordinator
            self.googlePIMAccessTokenProvider = googlePIMAccessTokenProvider
            self.localBackendFactory = localBackendFactory
        }
    }

    /// Creates a session with persistent account, credential, cache, and sync wiring.
    @MainActor
    public static func makeDefault(configuration: Configuration) -> AppSession {
        // ADR-0072: one serial owner for every PIM source. Records live in
        // Application Support/Brev, credentials only as Keychain references.
        let pimBrevDirectory = configuration.applicationSupportURL
            .appendingPathComponent("Brev", isDirectory: true)
        let pimLocalDataStore = FilePIMSourceLocalDataStore(
            rootURL: pimBrevDirectory.appendingPathComponent("PIMSources", isDirectory: true)
        )
        let pimSourceCoordinator = PIMSourceCoordinator(
            store: JSONPIMSourceStore(
                fileURL: pimBrevDirectory.appendingPathComponent("pim-sources.json")
            ),
            credentials: CalDAVKeychainCredentialStore(),
            localData: pimLocalDataStore
        )
        // ADR-0072 #6: collection discovery rides the same credential
        // paths — DAV sources via their Keychain reference, Google sources
        // via the linked account's shared grant.
        let pimCollectionService = PIMCollectionService(
            coordinator: pimSourceCoordinator,
            store: JSONPIMCollectionStore(localDataStore: pimLocalDataStore),
            credentials: CalDAVKeychainCredentialStore(),
            googleAccessToken: configuration.googlePIMAccessTokenProvider
        )
        // ADR-0072 #6: event sync rides the same credential paths and
        // per-source data directories; cursors live under the wiped-on-
        // removal cursor directory.
        let pimEventSyncService = PIMEventSyncService(
            coordinator: pimSourceCoordinator,
            collectionStore: JSONPIMCollectionStore(
                localDataStore: pimLocalDataStore
            ),
            eventStore: JSONPIMEventStore(localDataStore: pimLocalDataStore),
            cursorStore: JSONPIMSyncCursorStore(
                localDataStore: pimLocalDataStore
            ),
            credentials: CalDAVKeychainCredentialStore(),
            googleAccessToken: configuration.googlePIMAccessTokenProvider
        )

        // ADR-0072 #8: contacts sync rides the same credential paths and
        // per-source data directories; cursors live under the wiped-on-
        // removal cursor directory.
        let pimContactSyncService = PIMContactSyncService(
            coordinator: pimSourceCoordinator,
            collectionStore: JSONPIMCollectionStore(
                localDataStore: pimLocalDataStore
            ),
            contactStore: JSONPIMContactStore(
                localDataStore: pimLocalDataStore
            ),
            cursorStore: JSONPIMContactSyncCursorStore(
                localDataStore: pimLocalDataStore
            ),
            credentials: CalDAVKeychainCredentialStore(),
            googleAccessToken: configuration.googlePIMAccessTokenProvider
        )

        // ADR-0072 #7: event writes ride the same credential paths —
        // Google via the linked account grant (calendar.events scope),
        // CalDAV via the Keychain reference. The service only acts on
        // sources whose .write capability the user explicitly enabled.
        let pimEventWriteService = PIMEventWriteService(
            coordinator: pimSourceCoordinator,
            collectionStore: JSONPIMCollectionStore(
                localDataStore: pimLocalDataStore
            ),
            eventStore: JSONPIMEventStore(localDataStore: pimLocalDataStore),
            credentials: CalDAVKeychainCredentialStore(),
            googleAccessToken: configuration.googlePIMAccessTokenProvider
        )

        // ADR-0072 #9: contact writes ride the same credential paths —
        // Google via the linked account grant (contacts scope), CardDAV
        // via the Keychain reference. The service only acts on sources
        // whose .write capability the user explicitly enabled.
        let pimContactWriteService = PIMContactWriteService(
            coordinator: pimSourceCoordinator,
            contactStore: JSONPIMContactStore(
                localDataStore: pimLocalDataStore
            ),
            credentials: CalDAVKeychainCredentialStore(),
            googleAccessToken: configuration.googlePIMAccessTokenProvider
        )

        // ADR-0072 #12: task sync rides the same credential paths —
        // Google via the linked account grant (tasks.readonly scope),
        // CalDAV via the Keychain reference on VTODO-capable collections.
        let pimTaskSyncService = PIMTaskSyncService(
            coordinator: pimSourceCoordinator,
            collectionStore: JSONPIMCollectionStore(
                localDataStore: pimLocalDataStore
            ),
            taskStore: JSONPIMTaskStore(localDataStore: pimLocalDataStore),
            cursorStore: JSONPIMSyncCursorStore(
                localDataStore: pimLocalDataStore
            ),
            credentials: CalDAVKeychainCredentialStore(),
            googleAccessToken: configuration.googlePIMAccessTokenProvider
        )

        #if DEBUG
        if configuration.isDemoModeRequested() {
            let mock = configuration.makeDemoBackend()
            let store = InMemoryAccountStore(accounts: [mock.account], current: mock.account)
            return AppSession(
                backend: mock,
                accountStore: store,
                tokenStore: KeychainTokenStore(),
                loginCoordinator: {
                    AppSession.LoginResult(backend: mock, account: mock.account)
                },
                pimSourceCoordinator: pimSourceCoordinator,
                pimCollectionService: pimCollectionService,
                pimEventSyncService: pimEventSyncService,
                pimContactSyncService: pimContactSyncService,
                pimTaskSyncService: pimTaskSyncService,
                pimEventWriteService: pimEventWriteService,
                pimContactWriteService: pimContactWriteService,
                aiProviderAssignmentCleanup: cleanupAIProviderAssignment
            )
        }
        #endif

        let accountStore = UserDefaultsAccountStore()
        let configurationStore = UserDefaultsIMAPAccountConfigurationStore()
        let credentialStore = KeychainMailCredentialStore()
        let draftStagingStore = FileIMAPDraftStagingStore(
            rootDirectory: configuration.applicationSupportURL
                .appendingPathComponent("Brev/Drafts")
        )
        let tokenStore = KeychainTokenStore()
        let connector = IMAPAccountConnector.standard(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            localSearchIndex: configuration.localSearchIndex,
            draftStagingStore: draftStagingStore,
            offlineMutationQueue: { id in OfflineMutationQueueStorage.queue(accountID: id) },
            offlineMutationConflictStore: { id in
                OfflineMutationQueueStorage.conflictStore(accountID: id)
            },
            tokenStore: tokenStore,
            // S/MIME signing/encryption is backed by the local Keychain store.
            outboundMessagePreparer: OutboundMessagePreparerFactory.makeStandard()
        )

        #if DEBUG
        let demoLoginCoordinator: AppSession.DemoLoginCoordinator? = {
            let mock = configuration.makeDemoBackend()
            return AppSession.LoginResult(backend: mock, account: mock.account)
        }
        #else
        let demoLoginCoordinator: AppSession.DemoLoginCoordinator? = nil
        #endif

        let localBackend = (configuration.localBackendFactory ?? {
            LocalMailBackend(
                // Deferred so session bootstrap never blocks first paint on
                // the index's SQLite open/migration; it is only needed for
                // search and attachment indexing.
                localSearchIndex: configuration.localSearchIndex.map { factory in
                    DeferredLocalSearchIndex { factory(LocalMailBackend.accountID) }
                },
                attachmentIndexConsent: AttachmentIndexConsentStore.shared
            )
        })()

        let googleOAuthLoginCoordinator: AppSession.GoogleOAuthLoginCoordinator? =
            configuration.googleOAuthAccountProvisioningCoordinator.map { provisioner in
                {
                    try await IMAPOAuthLoginFlow.makeGoogleLoginResult(
                        presentationAnchor: configuration.oauthPresentationAnchor,
                        accountProvisioner: provisioner
                    )
                }
            }

        return AppSession(
            localBackend: localBackend,
            accountStore: accountStore,
            tokenStore: tokenStore,
            imapAccountSetupCoordinator: { request in
                let connected = try await connector.provisionAndConnect(request)
                return AppSession.LoginResult(
                    backend: connected.backend,
                    account: connected.account
                )
            },
            imapAccountValidationCoordinator: { request in
                try await connector.validate(request)
            },
            imapOAuthSetupCoordinator: { request in
                let connected = try await connector.provisionAndConnectOAuth(request)
                return AppSession.LoginResult(
                    backend: connected.backend,
                    account: connected.account
                )
            },
            imapOAuthBrowserCoordinator: { provider in
                try await IMAPOAuthLoginFlow.makeLoginResult(
                    provider: provider,
                    connector: connector,
                    tokenStore: tokenStore,
                    presentationAnchor: configuration.oauthPresentationAnchor
                )
            },
            googleOAuthLoginCoordinator: googleOAuthLoginCoordinator,
            googleOAuthIsConfigured: OAuthClientConfiguration.shared.canStartGoogleOAuth,
            imapAccountDiscoveryCoordinator: { emailAddress in
                // Discovery is user-initiated from account setup (ADR-0028).
                await MailAccountAutodiscovery.discover(forEmailAddress: emailAddress)
            },
            restoreCoordinator: { account in
                if account.backendIdentifier == BrevAccount.gmailAPIBackendIdentifier {
                    guard let googleOAuthRestoreCoordinator = configuration.googleOAuthRestoreCoordinator else {
                        return nil
                    }
                    return try await googleOAuthRestoreCoordinator(account)
                }
                guard let backend = try await connector.restore(account) else {
                    return nil
                }
                return AppSession.LoginResult(backend: backend, account: account)
            },
            demoLoginCoordinator: demoLoginCoordinator,
            signOutCoordinator: { account in
                if account.backendIdentifier == BrevAccount.gmailAPIBackendIdentifier {
                    guard let coordinator = configuration.googleOAuthRemovalCoordinator else {
                        throw AppSessionFactoryError.missingGoogleOAuthRemovalCoordinator
                    }
                    try await coordinator(account.id)
                    return
                }
                await connector.removeAccount(account.id)
            },
            pimSourceCoordinator: pimSourceCoordinator,
            pimCollectionService: pimCollectionService,
            pimEventSyncService: pimEventSyncService,
            pimContactSyncService: pimContactSyncService,
            pimTaskSyncService: pimTaskSyncService,
            pimEventWriteService: pimEventWriteService,
            pimContactWriteService: pimContactWriteService,
            googlePIMEnablementCoordinator: configuration.googlePIMEnablementCoordinator,
            aiProviderAssignmentCleanup: cleanupAIProviderAssignment
        )
    }

    /// Loads the account's configured compose signatures for the app root.
    public static func composeSignatureContext(for account: BrevAccount) -> ComposeSignatureContext {
        let settings = SettingsPersistenceStore.standard.signatureSettings()
        let signatureOptions = settings.signatures(forAccountID: account.id).map { signature in
            ComposeSignatureOption(
                id: signature.id,
                title: signature.name.isEmpty
                    ? String(localized: "Signature", bundle: .module)
                    : signature.name,
                body: signature.body
            )
        }
        return ComposeSignatureContext(
            selectedSignatureID: settings.defaultSignatureID(forAccountID: account.id),
            options: signatureOptions
        )
    }

    /// Resolves compose signing and encryption defaults from local settings.
    public static func composeSecurityDefaults(for _: BrevAccount) -> ComposeSecurityDefaultState {
        let encryptionSettings = EncryptionSettings.load()
        let keyMaterialSettings = SecurityKeyMaterialSettings.load()
        return ComposeSecurityDefaults.resolve(
            encryptionSettings: encryptionSettings,
            trustedSigningIdentityCount: keyMaterialSettings.trustedSigningRecordCount,
            trustedEncryptionIdentityCount: keyMaterialSettings.trustedEncryptionRecordCount
        )
    }

    /// Returns the number of locally trusted signing identities.
    public static func trustedSigningIdentityCount(for _: BrevAccount) -> Int {
        SecurityKeyMaterialSettings.load().trustedSigningRecordCount
    }

    /// Returns the number of locally trusted encryption identities.
    public static func trustedEncryptionIdentityCount(for _: BrevAccount) -> Int {
        SecurityKeyMaterialSettings.load().trustedEncryptionRecordCount
    }

    @MainActor
    private static func cleanupAIProviderAssignment(accountID: BrevAccount.ID) async {
        try? AIProviderAccountAssignmentStore().removeAccount(accountID)
    }
}
