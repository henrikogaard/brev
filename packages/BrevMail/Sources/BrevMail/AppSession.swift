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

import BrevAI
import BrevBackend
import BrevCalendar
import BrevSettings
import BrevThemes
import Foundation
import Observation

public enum IMAPOAuthProvider: Sendable, Hashable {
    case google
    case microsoft
}

/// Per ADR-0066: the app-level session state. Holds the currently
/// active `MailBackend` (or `nil` when no account is signed in),
/// the cross-platform `AccountStore`, and the active theme.
///
/// `LoginCoordinator` is injected by the app target. It returns a
/// fresh `MailBackend` plus its `BrevAccount` when interactive account
/// setup is available. Keeping the coordinator behind a closure means
/// `BrevMail` stays provider-agnostic.
@MainActor
@Observable
public final class AppSession {
    public var backend: (any MailBackend)?
    public private(set) var backends: [BrevAccount.ID: any MailBackend] = [:]
    public private(set) var aiBackends: [BrevAccount.ID: any AIBackend] = [:]
    public var aiBackend: (any AIBackend)?
    public var theme: BrevTheme {
        didSet {
            ThemePreferences.save(theme, defaults: themeDefaults)
        }
    }

    public var signInError: String?
    public var isSigningIn = false
    public var isRestoringSession = false
    public var canRetrySessionRestore = false
    /// True when native Gmail setup failed in a way that permits an explicit
    /// Google IMAP/XOAUTH2 retry through the injected fallback coordinator.
    public private(set) var canUseGoogleIMAPFallback = false
    public private(set) var pendingInitialMailboxSelectionAccountID: BrevAccount.ID?
    /// Set to the email address of an IMAP/SMTP account that failed to restore
    /// due to an authentication error. Used by `LoginView` to surface an
    /// "Update password" affordance pre-filled with the account's email.
    public private(set) var authFailedIMAPAccountEmail: String?
    /// Per-account restore error messages for accounts that failed to restore
    /// while at least one other account connected successfully.
    public private(set) var accountRestoreErrors: [BrevAccount.ID: String] = [:]

    public let accountStore: any AccountStore
    public let tokenStore: any TokenStore
    private let themeDefaults: UserDefaults

    public struct LoginResult {
        public let backend: any MailBackend
        public let account: BrevAccount
        public let aiBackend: (any AIBackend)?

        public init(
            backend: any MailBackend,
            account: BrevAccount,
            aiBackend: (any AIBackend)? = nil
        ) {
            self.backend = backend
            self.account = account
            self.aiBackend = aiBackend
        }
    }

    /// Performs platform-specific account setup. Returns the connected
    /// backend (already `connect()`ed) and the account it belongs to.
    /// Throws on cancellation or auth failure.
    public typealias LoginCoordinator = @MainActor () async throws -> LoginResult
    public typealias IMAPAccountSetupCoordinator =
        @MainActor (IMAPAccountSetupRequest) async throws -> LoginResult
    public typealias IMAPAccountValidationCoordinator =
        @MainActor (IMAPAccountSetupRequest) async throws -> Void
    /// Drives the OAuth2 account provisioning flow for Gmail and Outlook.
    ///
    /// The closure receives an `IMAPOAuthSetupRequest` carrying the access token
    /// obtained from `GoogleOAuthFlow` or `OutlookOAuthFlow`, provisions the IMAP
    /// account, and returns a connected `LoginResult`.
    public typealias IMAPOAuthSetupCoordinator =
        @MainActor (IMAPOAuthSetupRequest) async throws -> LoginResult
    public typealias IMAPOAuthBrowserCoordinator =
        @MainActor (IMAPOAuthProvider) async throws -> LoginResult
    /// Provisions a Google account after the shared OAuth flow has verified its
    /// identity. The result is kept intact so a provider API connector can use
    /// the stable subject, hosted domain, granted scopes, and token together.
    /// When this coordinator is absent, Google uses the existing IMAP/SMTP
    /// provisioning path.
    public typealias GoogleOAuthAccountProvisioningCoordinator =
        @MainActor (GoogleOAuthResult) async throws -> LoginResult
    /// Completes the injected Google OAuth flow and account provisioning path.
    /// This keeps the session coordinator provider-neutral while allowing the
    /// app factory to choose a Gmail API connector for Google accounts.
    public typealias GoogleOAuthLoginCoordinator =
        @MainActor () async throws -> LoginResult
    public typealias IMAPAccountDiscoveryCoordinator =
        @MainActor (String) async throws -> MailAccountDiscoveryResult
    public typealias RestoreCoordinator = @MainActor (BrevAccount) async throws -> LoginResult?
    public typealias DemoLoginCoordinator = @MainActor () async -> LoginResult
    public typealias CardDAVContactSyncStarter =
        @MainActor (ContactsSyncCoordinator, CardDAVConfiguration, String) -> Void

    /// Called when the user signs out: lets the host clear any
    /// non-Brev-owned state (revoke tokens server-side, etc).
    public typealias SignOutCoordinator = @MainActor (BrevAccount) async throws -> Void
    public typealias AccountDataCleanup = @MainActor (BrevAccount.ID) async -> Void
    public typealias AIProviderAssignmentCleanup = @MainActor (BrevAccount.ID) async -> Void
    public typealias PendingMutationCleanup = @MainActor (BrevAccount.ID) async -> Void

    private let loginCoordinator: LoginCoordinator?
    private let imapAccountSetupCoordinator: IMAPAccountSetupCoordinator?
    private let imapAccountValidationCoordinator: IMAPAccountValidationCoordinator?
    private let imapOAuthSetupCoordinator: IMAPOAuthSetupCoordinator?
    private let imapOAuthBrowserCoordinator: IMAPOAuthBrowserCoordinator?
    private let googleOAuthLoginCoordinator: GoogleOAuthLoginCoordinator?
    private let googleOAuthIsConfigured: Bool?
    private let imapAccountDiscoveryCoordinator: IMAPAccountDiscoveryCoordinator?
    private let restoreCoordinator: RestoreCoordinator?
    private let demoLoginCoordinator: DemoLoginCoordinator?
    private let cardDAVContactSyncStarter: CardDAVContactSyncStarter
    private let signOutCoordinator: SignOutCoordinator
    private let accountDataCleanup: AccountDataCleanup
    private let aiProviderAssignmentCleanup: AIProviderAssignmentCleanup
    private let aiProviderBackendResolver: AIProviderBackendResolver
    private let pendingMutationCleanup: PendingMutationCleanup
    private var builtInAIBackends: [BrevAccount.ID: any AIBackend] = [:]
    private var nextSignInRequestID = 0
    private var activeSignInRequest: AppSessionSignInRequest?
    private var nextRestoreRequestID = 0
    private var activeRestoreRequest: AppSessionRestoreRequest?
    private var signingOutAccountIDs: Set<BrevAccount.ID> = []

    public var canUseDemoAccount: Bool {
        demoLoginCoordinator != nil
    }

    public var canUseInteractiveSignIn: Bool {
        loginCoordinator != nil
    }

    public var canUseIMAPAccountSetup: Bool {
        imapAccountSetupCoordinator != nil
    }

    public var canValidateIMAPAccountSetup: Bool {
        imapAccountValidationCoordinator != nil
    }

    public var canUseIMAPOAuthSetup: Bool {
        imapOAuthSetupCoordinator != nil
    }

    public var canStartIMAPOAuthBrowserSetup: Bool {
        imapOAuthBrowserCoordinator != nil
    }

    /// Whether the host can start a Google-native or browser-based sign-in.
    /// The UI consumes this provider-neutral capability instead of inspecting
    /// the coordinator implementation or backend type.
    public var canStartGoogleSignIn: Bool {
        guard googleOAuthIsConfigured != false else { return false }
        return googleOAuthLoginCoordinator != nil || imapOAuthBrowserCoordinator != nil
    }

    /// Whether Google sign-in will provision the native Gmail API backend
    /// instead of the standards-based IMAP OAuth route.
    public var canStartNativeGoogleSignIn: Bool {
        guard googleOAuthIsConfigured != false else { return false }
        return googleOAuthLoginCoordinator != nil
    }

    public var canDiscoverIMAPSettings: Bool {
        imapAccountDiscoveryCoordinator != nil
    }

    public var isSigningOut: Bool {
        !signingOutAccountIDs.isEmpty
    }

    public var visibleBackends: [any MailBackend] {
        backends.values.sorted {
            $0.account.emailAddress.localizedCaseInsensitiveCompare(
                $1.account.emailAddress
            ) == .orderedAscending
        }
    }

    public init(
        theme: BrevTheme? = nil,
        initialSignInError: String? = nil,
        backend: (any MailBackend)? = nil,
        aiBackend: (any AIBackend)? = nil,
        accountStore: any AccountStore,
        tokenStore: any TokenStore,
        themeDefaults: UserDefaults = .standard,
        loginCoordinator: LoginCoordinator? = nil,
        imapAccountSetupCoordinator: IMAPAccountSetupCoordinator? = nil,
        imapAccountValidationCoordinator: IMAPAccountValidationCoordinator? = nil,
        imapOAuthSetupCoordinator: IMAPOAuthSetupCoordinator? = nil,
        imapOAuthBrowserCoordinator: IMAPOAuthBrowserCoordinator? = nil,
        googleOAuthLoginCoordinator: GoogleOAuthLoginCoordinator? = nil,
        googleOAuthIsConfigured: Bool? = nil,
        imapAccountDiscoveryCoordinator: IMAPAccountDiscoveryCoordinator? = nil,
        restoreCoordinator: RestoreCoordinator? = nil,
        demoLoginCoordinator: DemoLoginCoordinator? = nil,
        cardDAVContactSyncStarter: @escaping CardDAVContactSyncStarter = { coordinator, configuration, token in
            Task {
                try? await coordinator.sync(
                    configuration: configuration,
                    credential: .bearer(token: token)
                )
            }
        },
        signOutCoordinator: @escaping SignOutCoordinator = { _ in },
        accountDataCleanup: @escaping AccountDataCleanup = { _ in },
        aiProviderAssignmentCleanup: @escaping AIProviderAssignmentCleanup = { accountID in
            try? AIProviderAccountAssignmentStore().removeAccount(accountID)
        },
        aiProviderBackendResolver: AIProviderBackendResolver = AIProviderBackendResolver(),
        pendingMutationCleanup: @escaping PendingMutationCleanup = { _ in }
    ) {
        self.themeDefaults = themeDefaults
        self.theme = theme ?? ThemePreferences.load(defaults: themeDefaults)
        signInError = initialSignInError
        self.backend = backend
        self.aiBackend = aiBackend
        self.accountStore = accountStore
        self.tokenStore = tokenStore
        self.loginCoordinator = loginCoordinator
        self.imapAccountSetupCoordinator = imapAccountSetupCoordinator
        self.imapAccountValidationCoordinator = imapAccountValidationCoordinator
        self.imapOAuthSetupCoordinator = imapOAuthSetupCoordinator
        self.imapOAuthBrowserCoordinator = imapOAuthBrowserCoordinator
        self.googleOAuthLoginCoordinator = googleOAuthLoginCoordinator
        self.googleOAuthIsConfigured = googleOAuthIsConfigured
        self.imapAccountDiscoveryCoordinator = imapAccountDiscoveryCoordinator
        self.restoreCoordinator = restoreCoordinator
        self.demoLoginCoordinator = demoLoginCoordinator
        self.cardDAVContactSyncStarter = cardDAVContactSyncStarter
        self.signOutCoordinator = signOutCoordinator
        self.accountDataCleanup = accountDataCleanup
        self.aiProviderAssignmentCleanup = aiProviderAssignmentCleanup
        self.aiProviderBackendResolver = aiProviderBackendResolver
        self.pendingMutationCleanup = pendingMutationCleanup
        if let backend {
            backends[backend.account.id] = backend
            if let aiBackend {
                builtInAIBackends[backend.account.id] = aiBackend
                aiBackends[backend.account.id] = aiBackend
            }
        }
    }

    /// Refreshes the account-scoped AI routes after local provider settings change.
    ///
    /// This reads device-local metadata and Keychain secrets only. Constructing a
    /// route never contacts an AI endpoint; endpoints are contacted only by an
    /// explicit compose, summary, or mailbox-chat action.
    public func reloadConfiguredAIBackends() async {
        aiBackends = await aiProviderBackendResolver.backends(
            forAccountIDs: Array(backends.keys),
            builtInBackends: builtInAIBackends
        )
        aiBackend = backend.flatMap { aiBackends[$0.account.id] }
    }

    public func signIn(requestInitialMailboxSelection: Bool = true) async {
        guard let loginCoordinator,
              !isSigningIn,
              !isSigningOut else { return }
        invalidateRestore()
        let request = startSignInRequest(kind: .interactive)
        isSigningIn = true
        signInError = nil
        canRetrySessionRestore = false
        let existingAccountIDs = await storedAccountIDs()
        do {
            let result = try await loginCoordinator()
            let isNewAccount = !existingAccountIDs.contains(result.account.id)
            guard canApplySignInResponse(request) else {
                await discard(result)
                return
            }
            await install(result)
            if isNewAccount && requestInitialMailboxSelection {
                pendingInitialMailboxSelectionAccountID = result.account.id
            }
            finishSignIn(request)
        } catch is CancellationError {
            guard canApplySignInResponse(request) else { return }
            // User dismissed; not an error.
            finishSignIn(request)
        } catch {
            guard canApplySignInResponse(request) else { return }
            signInError = AppSessionPresentation.signInErrorMessage(for: error)
            finishSignIn(request)
        }
    }

    public func signIn(
        with request: IMAPAccountSetupRequest,
        requestInitialMailboxSelection: Bool = true
    ) async {
        guard let imapAccountSetupCoordinator,
              !isSigningIn,
              !isSigningOut else { return }
        invalidateRestore()
        let signInRequest = startSignInRequest(kind: .interactive)
        isSigningIn = true
        signInError = nil
        canRetrySessionRestore = false
        let existingAccountIDs = await storedAccountIDs()
        do {
            let result = try await imapAccountSetupCoordinator(request)
            let isNewAccount = !existingAccountIDs.contains(result.account.id)
            guard canApplySignInResponse(signInRequest) else {
                await discard(result)
                return
            }
            await install(result)
            if isNewAccount && requestInitialMailboxSelection {
                pendingInitialMailboxSelectionAccountID = result.account.id
            }
            finishSignIn(signInRequest)
        } catch is CancellationError {
            guard canApplySignInResponse(signInRequest) else { return }
            finishSignIn(signInRequest)
        } catch {
            guard canApplySignInResponse(signInRequest) else { return }
            signInError = AppSessionPresentation.signInErrorMessage(for: error)
            finishSignIn(signInRequest)
        }
    }

    /// Signs in using a completed OAuth2 flow result (Gmail or Outlook).
    ///
    /// The caller must have already obtained an access token from `GoogleOAuthFlow`
    /// or `OutlookOAuthFlow` and constructed an `IMAPOAuthSetupRequest` carrying
    /// the provider's IMAP/SMTP server settings. This method provisions the IMAP
    /// account, connects it, and adds it to the multi-source workspace.
    public func signIn(
        withOAuthRequest request: IMAPOAuthSetupRequest,
        requestInitialMailboxSelection: Bool = true
    ) async {
        guard let imapOAuthSetupCoordinator,
              !isSigningIn,
              !isSigningOut else { return }
        invalidateRestore()
        let signInRequest = startSignInRequest(kind: .interactive)
        isSigningIn = true
        signInError = nil
        canRetrySessionRestore = false
        let existingAccountIDs = await storedAccountIDs()
        do {
            let result = try await imapOAuthSetupCoordinator(request)
            let isNewAccount = !existingAccountIDs.contains(result.account.id)
            guard canApplySignInResponse(signInRequest) else {
                await discard(result)
                return
            }
            await install(result)
            if isNewAccount && requestInitialMailboxSelection {
                pendingInitialMailboxSelectionAccountID = result.account.id
            }
            finishSignIn(signInRequest)
        } catch is CancellationError {
            guard canApplySignInResponse(signInRequest) else { return }
            finishSignIn(signInRequest)
        } catch {
            guard canApplySignInResponse(signInRequest) else { return }
            signInError = AppSessionPresentation.signInErrorMessage(for: error)
            finishSignIn(signInRequest)
        }
    }

    public func signInWithIMAPOAuthProvider(
        _ provider: IMAPOAuthProvider,
        requestInitialMailboxSelection: Bool = true,
        useIMAPFallback: Bool = false
    ) async {
        guard !isSigningIn,
              !isSigningOut else { return }
        guard imapOAuthBrowserCoordinator != nil
            || (provider == .google && googleOAuthLoginCoordinator != nil) else {
            signInError = String(localized: "OAuth sign-in is not available in this build.", bundle: .module)
            return
        }
        invalidateRestore()
        let signInRequest = startSignInRequest(kind: .interactive)
        isSigningIn = true
        signInError = nil
        canUseGoogleIMAPFallback = false
        canRetrySessionRestore = false
        let existingAccountIDs = await storedAccountIDs()
        do {
            let result: LoginResult
            if provider == .google, !useIMAPFallback, let googleOAuthLoginCoordinator {
                result = try await googleOAuthLoginCoordinator()
            } else if let imapOAuthBrowserCoordinator {
                result = try await imapOAuthBrowserCoordinator(provider)
            } else {
                // The guard above covers this path; keep the fallback explicit
                // so a future provider cannot accidentally invoke the Google
                // connector.
                throw MailBackendError.backendSpecific(
                    message: "OAuth sign-in is not available in this build."
                )
            }
            let isNewAccount = !existingAccountIDs.contains(result.account.id)
            guard canApplySignInResponse(signInRequest) else {
                await discard(result)
                return
            }
            await install(result)
            if isNewAccount && requestInitialMailboxSelection {
                pendingInitialMailboxSelectionAccountID = result.account.id
            }
            finishSignIn(signInRequest)
        } catch is CancellationError {
            guard canApplySignInResponse(signInRequest) else { return }
            finishSignIn(signInRequest)
        } catch GoogleOAuthFlowError.userCancelled, OutlookOAuthFlowError.userCancelled {
            // Dismissing the OAuth sheet is a cancellation, not a failure —
            // finish quietly instead of surfacing a danger-tone error banner.
            guard canApplySignInResponse(signInRequest) else { return }
            finishSignIn(signInRequest)
        } catch {
            guard canApplySignInResponse(signInRequest) else { return }
            canUseGoogleIMAPFallback = provider == .google
                && !useIMAPFallback
                && imapOAuthBrowserCoordinator != nil
                && isNativeGoogleFallbackEligible(error)
            signInError = AppSessionPresentation.signInErrorMessage(for: error)
            finishSignIn(signInRequest)
        }
    }

    /// Retries a failed native Gmail sign-in explicitly through Google
    /// IMAP/XOAUTH2. This keeps admin-blocked or unavailable Gmail API access
    /// from silently changing the provider mode.
    public func signInWithGoogleIMAPFallback(
        requestInitialMailboxSelection: Bool = true
    ) async {
        guard canUseGoogleIMAPFallback else { return }
        await signInWithIMAPOAuthProvider(
            .google,
            requestInitialMailboxSelection: requestInitialMailboxSelection,
            useIMAPFallback: true
        )
    }

    /// Cancels the active interactive sign-in and ignores any result that
    /// arrives after the user has returned to the account chooser.
    public func cancelSignIn() {
        guard isSigningIn else { return }
        invalidateSignIn()
        signInError = nil
        canUseGoogleIMAPFallback = false
    }

    private func isNativeGoogleFallbackEligible(_ error: any Error) -> Bool {
        (error as? any IMAPFallbackEligibleError)?.isIMAPFallbackEligible == true
    }

    public func discoverIMAPSettings(
        forEmailAddress emailAddress: String
    ) async throws -> MailAccountDiscoveryResult {
        guard let imapAccountDiscoveryCoordinator else {
            throw MailAccountAutodiscoveryError.invalidEmailAddress
        }
        return try await imapAccountDiscoveryCoordinator(emailAddress)
    }

    public func validateIMAPAccountSetup(
        _ request: IMAPAccountSetupRequest
    ) async throws {
        guard let imapAccountValidationCoordinator else {
            throw MailBackendError.backendSpecific(
                message: IMAPAccountSetupPresentation.connectionTestUnavailableMessage
            )
        }
        try await imapAccountValidationCoordinator(request)
    }

    public func signInWithDemo() async {
        guard let demoLoginCoordinator else { return }
        guard !isSigningOut else { return }
        guard activeSignInRequest?.kind != .demo else { return }
        ContactsAccessPolicy.disableForDemoMailbox()
        invalidateRestore()
        let request = startSignInRequest(kind: .demo)
        isSigningIn = true
        signInError = nil
        canRetrySessionRestore = false

        let result = await demoLoginCoordinator()
        guard canApplySignInResponse(request) else {
            await discard(result)
            restoreContactsAccessIfNoDemoMailboxRemains()
            return
        }
        await install(result)
        finishSignIn(request)
    }

    public func restoreCurrentAccount() async {
        guard backend == nil,
              !isSigningIn,
              !isRestoringSession,
              let restoreCoordinator
        else {
            return
        }
        // Claim synchronously before any await so a concurrent re-entry is
        // rejected by the guard above instead of starting a second restore.
        isRestoringSession = true

        guard let account = await accountStore.current else {
            canRetrySessionRestore = false
            isRestoringSession = false
            return
        }
        guard !signingOutAccountIDs.contains(account.id) else {
            canRetrySessionRestore = false
            isRestoringSession = false
            return
        }

        let request = startRestoreRequest()
        // isRestoringSession was already claimed synchronously above.
        signInError = nil
        canRetrySessionRestore = false

        do {
            guard let result = try await restoreCoordinator(account) else {
                guard canApplyRestoreResponse(request) else { return }
                signInError = Self.incompleteStoredAccountMessage
                canRetrySessionRestore = true
                finishRestore(request)
                return
            }
            guard canApplyRestoreResponse(request) else {
                await discard(result)
                return
            }
            await install(result)
            finishRestore(request)
        } catch is CancellationError {
            guard canApplyRestoreResponse(request) else { return }
            // Restore is best-effort; a user cancellation is not an error.
            finishRestore(request)
        } catch {
            guard canApplyRestoreResponse(request) else { return }
            if Self.isAuthenticationRequired(error) {
                if shouldPurgeStoredAccountAfterAuthenticationFailure(account) {
                    await purgeStoredAccountAfterAuthenticationFailure(account)
                    canRetrySessionRestore = false
                } else {
                    canRetrySessionRestore = true
                    authFailedIMAPAccountEmail = account.emailAddress
                }
            } else {
                canRetrySessionRestore = true
            }
            signInError = AppSessionPresentation.restoreErrorMessage(for: error)
            finishRestore(request)
        }
    }

    /// Restores all stored accounts that are not yet connected.
    ///
    /// Unlike `restoreCurrentAccount()`, which only restores the account
    /// recorded as "current" in the account store, this method iterates
    /// every stored account and attempts a restore for each one. Failures
    /// for individual accounts are recorded in `accountRestoreErrors` so
    /// the UI can surface them without hiding a partially-working session.
    public func restoreAllAccounts() async {
        guard !isSigningIn, !isRestoringSession, restoreCoordinator != nil else { return }
        let startedAt = Date()
        defer {
            MailUIPerformanceDiagnostics.logStartupReady(
                surface: .sessionRestore,
                usableContent: !visibleBackends.isEmpty,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: startedAt)
            )
        }
        // Claim the restore synchronously, before any `await`. The guard above
        // reads `isRestoringSession`, but it was previously only set *after* the
        // two awaits below, so a second call arriving while this one was
        // suspended slipped through and ran a concurrent restore of the same
        // accounts (double `restoreCoordinator` calls). Setting it now closes
        // that window; reset on every early return.
        isRestoringSession = true

        let storedAccounts = await accountStore.accounts
        var toRestore = storedAccounts.filter {
            backends[$0.id] == nil && !signingOutAccountIDs.contains($0.id)
        }

        guard !toRestore.isEmpty else {
            if storedAccounts.isEmpty { canRetrySessionRestore = false }
            isRestoringSession = false
            return
        }

        // Restore the previously-active account first so UI can present a usable
        // mailbox ASAP. Remaining accounts restore afterward with bounded
        // concurrency so multi-account startup does not scale fully serially.
        let previousCurrentID = await accountStore.current?.id
        var preferredAccount: BrevAccount?
        if let idx = toRestore.firstIndex(where: { $0.id == previousCurrentID }) {
            preferredAccount = toRestore.remove(at: idx)
        }

        let request = startRestoreRequest()
        signInError = nil
        canRetrySessionRestore = false

        if let preferredAccount {
            await restoreOneAccount(preferredAccount, request: request, preserveAsCurrent: true)
        }

        let remaining = toRestore
        let maxConcurrentSecondaryRestores = 2
        var nextIndex = 0
        while nextIndex < remaining.count {
            guard canApplyRestoreResponse(request) else { break }
            let end = min(nextIndex + maxConcurrentSecondaryRestores, remaining.count)
            let batch = Array(remaining[nextIndex ..< end])
            nextIndex = end
            await withTaskGroup(of: Void.self) { group in
                for account in batch {
                    group.addTask { @MainActor in
                        await self.restoreOneAccount(
                            account,
                            request: request,
                            preserveAsCurrent: false
                        )
                    }
                }
                await group.waitForAll()
            }
        }

        // Ensure the preferred account remains focused after secondary installs.
        if let previousCurrentID,
           let preferredBackend = backends[previousCurrentID],
           canApplyRestoreResponse(request) {
            backend = preferredBackend
            aiBackend = aiBackends[previousCurrentID]
            await accountStore.setCurrent(previousCurrentID)
        }

        finishRestore(request)
    }

    private func restoreOneAccount(
        _ account: BrevAccount,
        request: AppSessionRestoreRequest,
        preserveAsCurrent: Bool
    ) async {
        guard canApplyRestoreResponse(request) else { return }
        do {
            guard let restoreCoordinator else { return }
            guard let result = try await restoreCoordinator(account) else {
                let message = Self.incompleteStoredAccountMessage
                accountRestoreErrors[account.id] = message
                signInError = message
                canRetrySessionRestore = true
                return
            }
            guard canApplyRestoreResponse(request) else {
                await discard(result)
                return
            }
            await install(result, makeCurrent: preserveAsCurrent)
        } catch is CancellationError {
            return
        } catch {
            guard canApplyRestoreResponse(request) else { return }
            let message = AppSessionPresentation.restoreErrorMessage(for: error)
            if Self.isAuthenticationRequired(error) {
                if shouldPurgeStoredAccountAfterAuthenticationFailure(account) {
                    await purgeStoredAccountAfterAuthenticationFailure(account)
                } else {
                    authFailedIMAPAccountEmail = account.emailAddress
                    accountRestoreErrors[account.id] = message
                    canRetrySessionRestore = true
                }
            } else {
                accountRestoreErrors[account.id] = message
                canRetrySessionRestore = true
            }
            signInError = message
        }
    }

    /// Clears all per-account restore error messages.
    ///
    /// Call this when the user dismisses the account-error alert so it
    /// does not re-appear during the current session.
    public func clearAccountRestoreErrors() {
        accountRestoreErrors = [:]
    }

    private static let incompleteStoredAccountMessage = String(
        localized: "Saved account settings are incomplete. Add the account again or update it in Settings.",
        bundle: .module
    )

    private static func isAuthenticationRequired(_ error: any Error) -> Bool {
        if case MailBackendError.authenticationRequired = error {
            return true
        }
        if case IMAPClientError.authenticationFailed = error {
            return true
        }
        return false
    }

    private func shouldPurgeStoredAccountAfterAuthenticationFailure(_ account: BrevAccount) -> Bool {
        // Preserve IMAP/SMTP accounts when authentication fails so the user can
        // fix credentials and retry without losing configuration. Legacy/remote
        // OAuth accounts are not preserved here because they usually require a
        // fresh sign-in flow.
        account.backendIdentifier != BrevAccount.imapSMTPBackendIdentifier
            && account.backendIdentifier != BrevAccount.gmailAPIBackendIdentifier
    }

    private func purgeStoredAccountAfterAuthenticationFailure(_ account: BrevAccount) async {
        await accountDataCleanup(account.id)
        await tokenStore.clearToken(for: account.id)
        await accountStore.remove(account.id)
        MailboxSourcePreferencesStorage.removeAccount(account.id)
        FolderVisibilityPreferencesStorage.removeAccount(account.id)
        FolderAliasPreferencesStorage.removeAccount(account.id)
        LocalMessageWorkflowStateStorage.removeAccount(account.id)
        SettingsPersistenceStore.standard.removeAccountScopedState(accountID: account.id)
        await pendingMutationCleanup(account.id)
        await aiProviderAssignmentCleanup(account.id)
    }

    public func signOut() async {
        guard let account = backend?.account else {
            invalidateSignIn()
            invalidateRestore()
            signInError = nil
            canRetrySessionRestore = false
            aiBackends.removeAll()
            builtInAIBackends.removeAll()
            return
        }
        await signOut(account: account)
    }

    public func signOut(account: BrevAccount) async {
        await endAccountSession(account, shouldRunSignOutCoordinator: true)
    }

    public func removeAccount(_ account: BrevAccount) async {
        await endAccountSession(account, shouldRunSignOutCoordinator: true)
    }

    /// Signals that the account needs to re-authenticate.
    ///
    /// Sets `authFailedIMAPAccountEmail` so `LoginView` shows the
    /// "Update password" prompt without disconnecting or removing the account.
    public func reauthenticate(account: BrevAccount) {
        authFailedIMAPAccountEmail = account.emailAddress
    }

    private func endAccountSession(
        _ account: BrevAccount,
        shouldRunSignOutCoordinator: Bool
    ) async {
        guard signingOutAccountIDs.insert(account.id).inserted else { return }
        defer { signingOutAccountIDs.remove(account.id) }
        invalidateSignIn()
        invalidateRestore()
        signInError = nil
        canRetrySessionRestore = false
        accountRestoreErrors[account.id] = nil
        let shouldRestoreNextAccount = backend?.account.id == account.id
        if let existing = backends.removeValue(forKey: account.id) {
            await existing.disconnect()
        }
        aiBackends[account.id] = nil
        builtInAIBackends[account.id] = nil
        if backend?.account.id == account.id {
            backend = nil
            aiBackend = nil
        }
        finishInitialMailboxSelection(for: account.id)
        if shouldRunSignOutCoordinator {
            do {
                try await signOutCoordinator(account)
            } catch {
                // Keep the account record and provider credentials so the user
                // can retry cleanup. The backend is disconnected above, but
                // removal is not reported as successful until provider-owned
                // local data has been deleted.
                signInError = AppSessionPresentation.restoreErrorMessage(for: error)
                canRetrySessionRestore = true
                accountRestoreErrors[account.id] = signInError
                restoreContactsAccessIfNoDemoMailboxRemains()
                return
            }
        }
        await accountDataCleanup(account.id)
        await tokenStore.clearToken(for: account.id)
        await accountStore.remove(account.id)
        MailboxSourcePreferencesStorage.removeAccount(account.id)
        FolderVisibilityPreferencesStorage.removeAccount(account.id)
        FolderAliasPreferencesStorage.removeAccount(account.id)
        LocalMessageWorkflowStateStorage.removeAccount(account.id)
        SettingsPersistenceStore.standard.removeAccountScopedState(accountID: account.id)
        await pendingMutationCleanup(account.id)
        await aiProviderAssignmentCleanup(account.id)
        if shouldRestoreNextAccount {
            if let next = visibleBackends.first {
                backend = next
                aiBackend = aiBackends[next.account.id]
                await accountStore.setCurrent(next.account.id)
            } else if await accountStore.current != nil {
                await restoreCurrentAccount()
            }
        }
        restoreContactsAccessIfNoDemoMailboxRemains()
    }

    public func finishInitialMailboxSelection(for accountID: BrevAccount.ID) {
        guard pendingInitialMailboxSelectionAccountID == accountID else { return }
        pendingInitialMailboxSelectionAccountID = nil
    }

    private func install(_ result: LoginResult, makeCurrent: Bool = true) async {
        if let existing = backends[result.account.id],
           (existing as AnyObject) !== (result.backend as AnyObject) {
            await existing.disconnect()
        }
        await accountStore.add(result.account)
        backends[result.account.id] = result.backend
        if let aiBackend = result.aiBackend {
            builtInAIBackends[result.account.id] = aiBackend
        } else {
            builtInAIBackends[result.account.id] = nil
        }
        await reloadConfiguredAIBackends()
        if makeCurrent {
            await accountStore.setCurrent(result.account.id)
            backend = result.backend
            aiBackend = aiBackends[result.account.id]
        } else if backend == nil {
            await accountStore.setCurrent(result.account.id)
            backend = result.backend
            aiBackend = aiBackends[result.account.id]
        }
        canRetrySessionRestore = false
        accountRestoreErrors[result.account.id] = nil
        if authFailedIMAPAccountEmail == result.account.emailAddress {
            authFailedIMAPAccountEmail = nil
        }
        injectCardDAVContactSync(result.backend)
    }

    private func restoreContactsAccessIfNoDemoMailboxRemains() {
        guard !backends.values.contains(where: { $0.account.backendIdentifier == "demo" }) else {
            return
        }
        ContactsAccessPolicy.restoreAfterDemoMailbox()
    }

    private func injectCardDAVContactSync(_ backend: any MailBackend) {
        guard let syncable = backend as? (any CardDAVContactSyncSupporting) else { return }
        let discovery = CalDAVDiscovery.discover(for: syncable.emailAddressForCardDAV)
        guard let carddavConfig = discovery.carddav else { return }
        guard let token = syncable.bearerTokenForCardDAV else { return }
        let coordinator = ContactsSyncCoordinator()
        syncable.setContactLookupProvider(CardDAVContactLookupAdapter(coordinator: coordinator))
        cardDAVContactSyncStarter(coordinator, carddavConfig, token)
    }

    private func storedAccountIDs() async -> Set<BrevAccount.ID> {
        await Set(accountStore.accounts.map(\.id))
    }

    private func discard(_ result: LoginResult) async {
        if backends.values.contains(where: { ($0 as AnyObject) === (result.backend as AnyObject) }) {
            return
        }
        await result.backend.disconnect()
    }

    private func startSignInRequest(
        kind: AppSessionSignInRequest.Kind
    ) -> AppSessionSignInRequest {
        nextSignInRequestID += 1
        let request = AppSessionSignInRequest(
            id: nextSignInRequestID,
            kind: kind
        )
        activeSignInRequest = request
        return request
    }

    private func canApplySignInResponse(_ request: AppSessionSignInRequest) -> Bool {
        AppSessionSignInResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeSignInRequest
        )
    }

    private func invalidateSignIn() {
        activeSignInRequest = nil
        isSigningIn = false
    }

    private func finishSignIn(_ request: AppSessionSignInRequest) {
        guard activeSignInRequest == request else { return }
        activeSignInRequest = nil
        isSigningIn = false
    }

    private func startRestoreRequest() -> AppSessionRestoreRequest {
        nextRestoreRequestID += 1
        let request = AppSessionRestoreRequest(id: nextRestoreRequestID)
        activeRestoreRequest = request
        return request
    }

    private func canApplyRestoreResponse(_ request: AppSessionRestoreRequest) -> Bool {
        AppSessionRestoreResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeRestoreRequest
        )
    }

    private func invalidateRestore() {
        activeRestoreRequest = nil
        isRestoringSession = false
    }

    private func finishRestore(_ request: AppSessionRestoreRequest) {
        guard activeRestoreRequest == request else { return }
        activeRestoreRequest = nil
        isRestoringSession = false
    }
}
