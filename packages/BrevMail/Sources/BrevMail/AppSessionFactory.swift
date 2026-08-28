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
            (@MainActor (BrevAccount.ID) async throws -> Void)? = nil
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
        }
    }

    /// Creates a session with persistent account, credential, cache, and sync wiring.
    @MainActor
    public static func makeDefault(configuration: Configuration) -> AppSession {
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
                aiProviderAssignmentCleanup: cleanupAIProviderAssignment
            )
        }

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
