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
import BrevMail
import Foundation
import Testing

@Suite("AppSession")
@MainActor
struct AppSessionTests {
    @Test("signIn stores optional AI backend and signOut clears it")
    func signInStoresAIBackend() async {
        let backend = MockBackend()
        let aiBackend = StubAIBackend()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(
                backend: backend,
                account: backend.account,
                aiBackend: aiBackend
            )
        }

        await session.signIn()

        #expect(session.backend?.account.id == backend.account.id)
        #expect(session.aiBackend?.identifier == aiBackend.identifier)
        #expect(session.aiBackends[backend.account.id]?.identifier == aiBackend.identifier)

        await session.signOut()

        #expect(session.backend == nil)
        #expect(session.aiBackend == nil)
        #expect(session.aiBackends.isEmpty)
        #expect(await session.accountStore.current == nil)
    }

    @Test("interactive sign-in marks the account for first-run mailbox setup")
    func interactiveSignInMarksAccountForFirstRunMailboxSetup() async {
        let backend = MockBackend()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(backend: backend, account: backend.account)
        }

        await session.signIn()

        #expect(session.pendingInitialMailboxSelectionAccountID == backend.account.id)

        session.finishInitialMailboxSelection(for: backend.account.id)

        #expect(session.pendingInitialMailboxSelectionAccountID == nil)
    }

    @Test("session restore does not mark account for first-run mailbox setup")
    func sessionRestoreDoesNotMarkAccountForFirstRunMailboxSetup() async {
        let account = BrevAccount(
            id: "stored",
            displayName: "Stored",
            emailAddress: "stored@example.org"
        )
        let backend = MockBackend(account: account)
        let session = AppSession(
            accountStore: InMemoryAccountStore(accounts: [account], current: account),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: backend, account: account)
            },
            restoreCoordinator: { _ in
                AppSession.LoginResult(backend: backend, account: account)
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.pendingInitialMailboxSelectionAccountID == nil)
    }

    @Test("interactive sign-in for an existing account does not restart mailbox setup")
    func interactiveSignInForExistingAccountDoesNotRestartMailboxSetup() async {
        let account = BrevAccount(
            id: "existing",
            displayName: "Existing",
            emailAddress: "existing@example.org"
        )
        let backend = MockBackend(account: account)
        let session = AppSession(
            accountStore: InMemoryAccountStore(accounts: [account], current: account),
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(backend: backend, account: account)
        }

        await session.signIn()

        #expect(session.pendingInitialMailboxSelectionAccountID == nil)
    }

    @Test("interactive sign-in can opt out of first-run mailbox setup")
    func interactiveSignInCanOptOutOfFirstRunMailboxSetup() async {
        let backend = MockBackend()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(backend: backend, account: backend.account)
        }

        await session.signIn(requestInitialMailboxSelection: false)

        #expect(session.pendingInitialMailboxSelectionAccountID == nil)
    }

    @Test("sign-out removes only that account's AI backend and restores the next account provider")
    func signOutRemovesOnlyThatAccountsAIBackend() async {
        let previousAccount = BrevAccount(
            id: "previous",
            displayName: "Previous",
            emailAddress: "previous@example.org"
        )
        let nextAccount = BrevAccount(
            id: "next",
            displayName: "Next",
            emailAddress: "next@example.org"
        )
        let previousBackend = DisconnectTrackingBackend(account: previousAccount)
        let nextBackend = DisconnectTrackingBackend(account: nextAccount)
        let previousAIBackend = StubAIBackend(identifier: "previous-ai")
        let nextAIBackend = StubAIBackend(identifier: "next-ai")
        let accountStore = InMemoryAccountStore(accounts: [previousAccount], current: previousAccount)
        let session = AppSession(
            backend: previousBackend,
            aiBackend: previousAIBackend,
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(
                backend: nextBackend,
                account: nextAccount,
                aiBackend: nextAIBackend
            )
        }

        await session.signIn()
        await session.signOut(account: nextAccount)

        #expect(session.backend?.account == previousAccount)
        #expect(session.aiBackend?.identifier == previousAIBackend.identifier)
        #expect(session.aiBackends[previousAccount.id]?.identifier == previousAIBackend.identifier)
        #expect(session.aiBackends[nextAccount.id] == nil)
    }

    @Test("sign-out runs AI provider assignment cleanup for removed accounts")
    func signOutRunsAIProviderAssignmentCleanup() async {
        let backend = MockBackend()
        var cleanedAccountIDs: [BrevAccount.ID] = []
        let session = AppSession(
            backend: backend,
            accountStore: InMemoryAccountStore(accounts: [backend.account], current: backend.account),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                AppSession.LoginResult(backend: backend, account: backend.account)
            },
            aiProviderAssignmentCleanup: { accountID in
                cleanedAccountIDs.append(accountID)
            }
        )

        await session.signOut()

        #expect(cleanedAccountIDs == [backend.account.id])
    }

    @Test("removeAccount runs provider sign-out and local account data cleanup")
    func removeAccountRunsProviderSignOutAndLocalDataCleanup() async {
        let backend = MockBackend()
        let recorder = AccountDataCleanupRecorder()
        let session = AppSession(
            backend: backend,
            accountStore: InMemoryAccountStore(accounts: [backend.account], current: backend.account),
            tokenStore: InMemoryTokenStore(),
            signOutCoordinator: { _ in await recorder.recordSignOut() },
            accountDataCleanup: { accountID in
                await recorder.recordCleanup(accountID)
            }
        )

        await session.removeAccount(backend.account)

        #expect(await recorder.signOutCalls == 1)
        #expect(await recorder.cleanedAccountIDs == [backend.account.id])
    }

    @Test("sign-out clears the account's stored token (#124)")
    func signOutClearsStoredToken() async {
        let backend = MockBackend()
        let tokenStore = InMemoryTokenStore()
        await tokenStore.setToken(
            Token(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date(timeIntervalSince1970: 9_999_999_999)
            ),
            for: backend.account.id
        )
        #expect(await tokenStore.token(for: backend.account.id) != nil)

        let session = AppSession(
            backend: backend,
            accountStore: InMemoryAccountStore(accounts: [backend.account], current: backend.account),
            tokenStore: tokenStore
        )

        await session.signOut()

        // The token must be gone after sign-out — explicit token-clearing proof.
        #expect(await tokenStore.token(for: backend.account.id) == nil)
    }

    @Test("signIn keeps the previously active backend when adding a different account")
    func signInKeepsPreviousBackendWhenAddingDifferentAccount() async {
        let previousAccount = BrevAccount(
            id: "previous",
            displayName: "Previous",
            emailAddress: "previous@example.org"
        )
        let nextAccount = BrevAccount(
            id: "next",
            displayName: "Next",
            emailAddress: "next@example.org"
        )
        let previousBackend = DisconnectTrackingBackend(account: previousAccount)
        let nextBackend = DisconnectTrackingBackend(account: nextAccount)
        let accountStore = InMemoryAccountStore(accounts: [previousAccount], current: previousAccount)
        let session = AppSession(
            backend: previousBackend,
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(backend: nextBackend, account: nextAccount)
        }

        await session.signIn()

        #expect(await previousBackend.disconnectCount == 0)
        #expect(await nextBackend.disconnectCount == 0)
        #expect(session.backend?.account == nextAccount)
        #expect(session.visibleBackends.map { $0.account.id }.sorted() == [
            nextAccount.id,
            previousAccount.id,
        ])
        #expect(await accountStore.accounts == [previousAccount, nextAccount])
        #expect(await accountStore.current == nextAccount)
    }

    @Test("signIn replaces an existing backend for the same account")
    func signInReplacesExistingBackendForSameAccount() async {
        let account = BrevAccount(
            id: "existing",
            displayName: "Existing",
            emailAddress: "existing@example.org"
        )
        let previousBackend = DisconnectTrackingBackend(account: account)
        let nextBackend = DisconnectTrackingBackend(account: account)
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let session = AppSession(
            backend: previousBackend,
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(backend: nextBackend, account: account)
        }

        await session.signIn()

        #expect(await previousBackend.disconnectCount == 1)
        #expect(await nextBackend.disconnectCount == 0)
        #expect(session.backend?.account == account)
        #expect(session.visibleBackends.map { $0.account.id } == [account.id])
        #expect(await accountStore.accounts == [account])
        #expect(await accountStore.current == account)
    }

    @Test("demo sign-in wins over a slow interactive sign-in")
    func demoSignInWinsOverSlowInteractiveSignIn() async {
        let interactiveAccount = BrevAccount(
            id: "interactive",
            displayName: "Interactive",
            emailAddress: "interactive@example.org"
        )
        let demoAccount = BrevAccount(
            id: "demo",
            displayName: "Demo",
            emailAddress: "demo@example.org"
        )
        let interactiveBackend = DisconnectTrackingBackend(account: interactiveAccount)
        let demoBackend = MockBackend(account: demoAccount)
        let signInGate = AsyncGate()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                await signInGate.markStarted()
                await signInGate.waitForResume()
                return AppSession.LoginResult(backend: interactiveBackend, account: interactiveAccount)
            },
            demoLoginCoordinator: {
                AppSession.LoginResult(backend: demoBackend, account: demoAccount)
            }
        )

        let signInTask = Task { await session.signIn() }
        await signInGate.waitUntilStarted()
        await session.signInWithDemo()
        await signInGate.resume()
        await signInTask.value

        #expect(session.backend?.account == demoAccount)
        #expect(await session.accountStore.current == demoAccount)
        #expect(await interactiveBackend.disconnectCount == 1)
    }

    @Test("duplicate demo sign-in requests do not start another demo flow")
    func duplicateDemoSignInRequestsAreIgnored() async {
        let demoAccount = BrevAccount(
            id: "demo",
            displayName: "Demo",
            emailAddress: "demo@example.org"
        )
        let duplicateAccount = BrevAccount(
            id: "duplicate-demo",
            displayName: "Duplicate Demo",
            emailAddress: "duplicate-demo@example.org"
        )
        let demoBackend = MockBackend(account: demoAccount)
        let duplicateBackend = MockBackend(account: duplicateAccount)
        let demoGate = AsyncGate()
        var demoAttempts = 0
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("OAuth coordinator should not run for demo sign-in")
                return AppSession.LoginResult(backend: demoBackend, account: demoAccount)
            },
            demoLoginCoordinator: {
                demoAttempts += 1
                if demoAttempts == 1 {
                    await demoGate.markStarted()
                    await demoGate.waitForResume()
                    return AppSession.LoginResult(backend: demoBackend, account: demoAccount)
                }
                return AppSession.LoginResult(
                    backend: duplicateBackend,
                    account: duplicateAccount
                )
            }
        )

        let firstDemoSignIn = Task { await session.signInWithDemo() }
        await demoGate.waitUntilStarted()
        await session.signInWithDemo()

        #expect(demoAttempts == 1)
        #expect(session.backend == nil)

        await demoGate.resume()
        await firstDemoSignIn.value

        #expect(session.backend?.account == demoAccount)
    }

    @Test("duplicate interactive sign-in requests do not start another OAuth flow")
    func duplicateInteractiveSignInRequestsAreIgnored() async {
        let account = BrevAccount(
            id: "interactive",
            displayName: "Interactive",
            emailAddress: "interactive@example.org"
        )
        let duplicateAccount = BrevAccount(
            id: "duplicate",
            displayName: "Duplicate",
            emailAddress: "duplicate@example.org"
        )
        let backend = MockBackend(account: account)
        let duplicateBackend = MockBackend(account: duplicateAccount)
        let signInGate = AsyncGate()
        var loginAttempts = 0
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                loginAttempts += 1
                if loginAttempts == 1 {
                    await signInGate.markStarted()
                    await signInGate.waitForResume()
                    return AppSession.LoginResult(backend: backend, account: account)
                }
                return AppSession.LoginResult(
                    backend: duplicateBackend,
                    account: duplicateAccount
                )
            }
        )

        let firstSignIn = Task { await session.signIn() }
        await signInGate.waitUntilStarted()
        await session.signIn()

        #expect(loginAttempts == 1)
        #expect(session.backend == nil)

        await signInGate.resume()
        await firstSignIn.value

        #expect(session.backend?.account == account)
    }

    @Test("sign out wins over a slow interactive sign-in")
    func signOutWinsOverSlowInteractiveSignIn() async {
        let storedAccount = BrevAccount(
            id: "stored",
            displayName: "Stored",
            emailAddress: "stored@example.org"
        )
        let interactiveAccount = BrevAccount(
            id: "interactive",
            displayName: "Interactive",
            emailAddress: "interactive@example.org"
        )
        let interactiveBackend = DisconnectTrackingBackend(account: interactiveAccount)
        let accountStore = InMemoryAccountStore(accounts: [storedAccount], current: storedAccount)
        let signInGate = AsyncGate()
        var signedOutAccounts: [BrevAccount] = []
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                await signInGate.markStarted()
                await signInGate.waitForResume()
                return AppSession.LoginResult(backend: interactiveBackend, account: interactiveAccount)
            },
            signOutCoordinator: { signedOutAccounts.append($0) }
        )

        let signInTask = Task { await session.signIn() }
        await signInGate.waitUntilStarted()
        await session.signOut(account: storedAccount)
        await signInGate.resume()
        await signInTask.value

        #expect(session.backend == nil)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(signedOutAccounts == [storedAccount])
        #expect(await interactiveBackend.disconnectCount == 1)
    }

    @Test("signIn uses a fallback message when the login error description is blank")
    func signInUsesFallbackMessageForBlankLoginError() async {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        ) {
            throw NSError(domain: "BrevTests", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])
        }

        await session.signIn()

        #expect(session.signInError == "Couldn't sign in.")
    }

    @Test("interactive sign-in can be unavailable while account setup is unavailable")
    func interactiveSignInCanBeUnavailableWhileAccountSetupIsUnavailable() async {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        )

        #expect(!session.canUseInteractiveSignIn)

        await session.signIn()

        #expect(session.backend == nil)
        #expect(session.signInError == nil)
    }

    @Test("IMAP account setup sign-in installs the connected backend")
    func imapAccountSetupSignInInstallsBackend() async {
        let backend = MockBackend(account: BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        ))
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )
        var capturedRequest: IMAPAccountSetupRequest?
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapAccountSetupCoordinator: { setupRequest in
                capturedRequest = setupRequest
                return AppSession.LoginResult(
                    backend: backend,
                    account: backend.account
                )
            }
        )

        #expect(session.canUseIMAPAccountSetup)

        await session.signIn(with: request)

        #expect(capturedRequest == request)
        #expect(session.backend?.account.id == "imap-smtp:person@example.org")
        #expect(await session.accountStore.current == backend.account)
    }

    @Test("IMAP account setup marks account new even when connector stores it before returning")
    func imapAccountSetupMarksAccountNewWhenConnectorStoresBeforeReturning() async {
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let backend = MockBackend(account: account)
        let accountStore = InMemoryAccountStore()
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            imapAccountSetupCoordinator: { _ in
                await accountStore.add(account)
                await accountStore.setCurrent(account.id)
                return AppSession.LoginResult(
                    backend: backend,
                    account: account
                )
            }
        )

        await session.signIn(with: request)

        #expect(session.pendingInitialMailboxSelectionAccountID == account.id)
    }

    @Test("OAuth browser setup coordinator is invoked with provider and installs backend")
    func oauthBrowserSetupCoordinatorIsInvoked() async {
        let account = BrevAccount(
            id: "imap-smtp:person@gmail.com",
            displayName: "Person",
            emailAddress: "person@gmail.com"
        )
        let backend = MockBackend(account: account)
        var capturedProvider: IMAPOAuthProvider?
        let session = AppSession(
            initialSignInError: "Previous error",
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapOAuthBrowserCoordinator: { provider in
                capturedProvider = provider
                return AppSession.LoginResult(
                    backend: backend,
                    account: account
                )
            }
        )

        #expect(session.canStartIMAPOAuthBrowserSetup)

        await session.signInWithIMAPOAuthProvider(.google)

        #expect(capturedProvider == .google)
        #expect(session.backend?.account == account)
        #expect(await session.accountStore.current == account)
        #expect(session.pendingInitialMailboxSelectionAccountID == account.id)
        #expect(session.signInError == nil)
    }

    @Test("Google sign-in availability is provider-neutral and prefers either Google path")
    func googleSignInAvailabilityIsProviderNeutral() {
        let browserSession = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapOAuthBrowserCoordinator: { _ in
                fatalError("not called")
            }
        )
        #expect(browserSession.canStartGoogleSignIn)
        #expect(!browserSession.canStartNativeGoogleSignIn)

        let unconfiguredSession = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapOAuthBrowserCoordinator: { _ in
                fatalError("not called")
            },
            googleOAuthIsConfigured: false
        )
        #expect(!unconfiguredSession.canStartGoogleSignIn)

        let nativeSession = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            googleOAuthLoginCoordinator: {
                fatalError("not called")
            }
        )
        #expect(nativeSession.canStartGoogleSignIn)
        #expect(nativeSession.canStartNativeGoogleSignIn)

        let unavailableSession = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        )
        #expect(!unavailableSession.canStartGoogleSignIn)
    }

    @Test("Google OAuth uses the injected native account connector")
    func googleOAuthUsesInjectedNativeAccountConnector() async {
        let googleAccount = BrevAccount(
            id: "gmail-api:google-subject",
            displayName: "Google",
            emailAddress: "person@gmail.com",
            backendIdentifier: "gmail-api",
            backendDisplayName: "Gmail"
        )
        let googleBackend = MockBackend(account: googleAccount)
        let imapBackend = MockBackend(
            account: BrevAccount(
                id: "imap-smtp:person@gmail.com",
                displayName: "IMAP",
                emailAddress: "person@gmail.com"
            )
        )
        var nativeAttempts = 0
        var fallbackAttempts = 0
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapOAuthBrowserCoordinator: { provider in
                #expect(provider == .microsoft)
                fallbackAttempts += 1
                return AppSession.LoginResult(backend: imapBackend, account: imapBackend.account)
            },
            googleOAuthLoginCoordinator: {
                nativeAttempts += 1
                return AppSession.LoginResult(backend: googleBackend, account: googleAccount)
            }
        )

        await session.signInWithIMAPOAuthProvider(.google)

        #expect(nativeAttempts == 1)
        #expect(fallbackAttempts == 0)
        #expect(session.backend?.account == googleAccount)
        #expect(session.backend?.account.backendIdentifier == "gmail-api")

        await session.signOut()
        await session.signInWithIMAPOAuthProvider(.microsoft)

        #expect(fallbackAttempts == 1)
        #expect(session.backend?.account == imapBackend.account)
    }

    @Test("Google OAuth cancellation through the native connector is quiet")
    func googleOAuthNativeConnectorCancellationIsQuiet() async {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            googleOAuthLoginCoordinator: {
                throw CancellationError()
            }
        )

        await session.signInWithIMAPOAuthProvider(.google)

        #expect(session.backend == nil)
        #expect(session.signInError == nil)
        #expect(!session.isSigningIn)
    }

    @Test("native Google policy failure exposes an explicit IMAP fallback")
    func nativeGooglePolicyFailureExposesIMAPFallback() async {
        let fallbackAccount = BrevAccount(
            id: "imap-smtp:person@gmail.com",
            displayName: "Google IMAP",
            emailAddress: "person@gmail.com"
        )
        let fallbackBackend = MockBackend(account: fallbackAccount)
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapOAuthBrowserCoordinator: { provider in
                #expect(provider == .google)
                return AppSession.LoginResult(backend: fallbackBackend, account: fallbackAccount)
            },
            googleOAuthLoginCoordinator: {
                throw NativeSetupFallbackError()
            }
        )

        await session.signInWithIMAPOAuthProvider(.google)
        #expect(session.canUseGoogleIMAPFallback)
        #expect(session.backend == nil)

        await session.signInWithGoogleIMAPFallback()
        #expect(session.backend?.account == fallbackAccount)
        #expect(!session.canUseGoogleIMAPFallback)
    }

    @Test("sign out wins over a slow native Google connector")
    func signOutWinsOverSlowNativeGoogleConnector() async {
        let googleAccount = BrevAccount(
            id: "gmail-api:slow-subject",
            displayName: "Google",
            emailAddress: "slow@gmail.com",
            backendIdentifier: "gmail-api",
            backendDisplayName: "Gmail"
        )
        let googleBackend = DisconnectTrackingBackend(account: googleAccount)
        let signInGate = AsyncGate()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            googleOAuthLoginCoordinator: {
                await signInGate.markStarted()
                await signInGate.waitForResume()
                return AppSession.LoginResult(backend: googleBackend, account: googleAccount)
            }
        )

        let signInTask = Task { await session.signInWithIMAPOAuthProvider(.google) }
        await signInGate.waitUntilStarted()
        await session.signOut()
        await signInGate.resume()
        await signInTask.value

        #expect(session.backend == nil)
        #expect(session.signInError == nil)
        #expect(await googleBackend.disconnectCount == 1)
    }

    @Test("cancelling a slow Google sign-in restores controls and discards a late result")
    func cancelGoogleSignInDiscardsLateResult() async {
        let googleAccount = BrevAccount(
            id: "gmail-api:cancelled-subject",
            displayName: "Google",
            emailAddress: "cancelled@gmail.com",
            backendIdentifier: "gmail-api",
            backendDisplayName: "Gmail"
        )
        let googleBackend = DisconnectTrackingBackend(account: googleAccount)
        let signInGate = AsyncGate()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            googleOAuthLoginCoordinator: {
                await signInGate.markStarted()
                await signInGate.waitForResume()
                return AppSession.LoginResult(backend: googleBackend, account: googleAccount)
            }
        )

        let signInTask = Task { await session.signInWithIMAPOAuthProvider(.google) }
        await signInGate.waitUntilStarted()
        #expect(session.isSigningIn)

        session.cancelSignIn()
        #expect(!session.isSigningIn)
        #expect(session.signInError == nil)

        await signInGate.resume()
        await signInTask.value

        #expect(session.backend == nil)
        #expect(await googleBackend.disconnectCount == 1)
    }

    @Test("OAuth browser setup adds backend beside existing password IMAP account")
    func oauthBrowserSetupAddsBackendBesideExistingPasswordIMAPAccount() async {
        let passwordAccount = BrevAccount(
            id: "imap-smtp:password@example.org",
            displayName: "Password",
            emailAddress: "password@example.org"
        )
        let oauthAccount = BrevAccount(
            id: "imap-smtp:person@gmail.com",
            displayName: "Person",
            emailAddress: "person@gmail.com"
        )
        let passwordBackend = MockBackend(account: passwordAccount)
        let oauthBackend = MockBackend(account: oauthAccount)
        let accountStore = InMemoryAccountStore(accounts: [passwordAccount], current: passwordAccount)
        let session = AppSession(
            backend: passwordBackend,
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            imapOAuthBrowserCoordinator: { provider in
                #expect(provider == .google)
                return AppSession.LoginResult(
                    backend: oauthBackend,
                    account: oauthAccount
                )
            }
        )

        await session.signInWithIMAPOAuthProvider(.google)

        #expect(session.backend?.account == oauthAccount)
        #expect(session.visibleBackends.map(\.account.id) == [
            "imap-smtp:password@example.org",
            "imap-smtp:person@gmail.com",
        ])
        #expect(await accountStore.accounts == [passwordAccount, oauthAccount])
        #expect(await accountStore.current == oauthAccount)
    }

    @Test("OAuth browser setup no-ops while another sign-in is active")
    func oauthBrowserSetupNoOpsWhileAnotherSignInIsActive() async {
        let account = BrevAccount(
            id: "interactive",
            displayName: "Interactive",
            emailAddress: "interactive@example.org"
        )
        let backend = MockBackend(account: account)
        let signInGate = AsyncGate()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                await signInGate.markStarted()
                await signInGate.waitForResume()
                return AppSession.LoginResult(backend: backend, account: account)
            }
        )

        let signInTask = Task { await session.signIn() }
        await signInGate.waitUntilStarted()
        await session.signInWithIMAPOAuthProvider(.google)

        #expect(session.isSigningIn)
        #expect(session.signInError == nil)
        #expect(session.backend == nil)

        await signInGate.resume()
        await signInTask.value

        #expect(session.backend?.account == account)
    }

    @Test("IMAP account setup validation delegates without installing backend")
    func imapAccountSetupValidationDelegatesWithoutInstallingBackend() async throws {
        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "app-password",
            discovery: MailAccountAutodiscovery.manualFallback(
                forEmailAddress: "person@example.org"
            )
        )
        var capturedRequest: IMAPAccountSetupRequest?
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapAccountValidationCoordinator: { setupRequest in
                capturedRequest = setupRequest
            }
        )

        #expect(session.canValidateIMAPAccountSetup)

        try await session.validateIMAPAccountSetup(request)

        #expect(capturedRequest == request)
        #expect(session.backend == nil)
        #expect(await session.accountStore.current == nil)
    }

    @Test("IMAP account discovery delegates to the injected resolver")
    func imapAccountDiscoveryDelegatesToInjectedResolver() async throws {
        var requestedEmailAddress: String?
        let expected = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            imapAccountDiscoveryCoordinator: { emailAddress in
                requestedEmailAddress = emailAddress
                return expected
            }
        )

        #expect(session.canDiscoverIMAPSettings)

        let result = try await session.discoverIMAPSettings(
            forEmailAddress: "person@example.org"
        )

        #expect(requestedEmailAddress == "person@example.org")
        #expect(result == expected)
    }

    @Test("initial sign-in guidance is visible before any interaction")
    func initialSignInGuidanceIsVisible() async {
        let session = AppSession(
            initialSignInError: "OAuth client configuration is missing.",
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        ) {
            Issue.record("Interactive sign-in should not run while checking initial guidance")
            return AppSession.LoginResult(backend: MockBackend(), account: MockBackend().account)
        }

        #expect(session.signInError == "OAuth client configuration is missing.")
    }

    @Test("demo sign-in is optional and stores the demo backend")
    func demoSignInStoresBackend() async {
        let backend = MockBackend()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("OAuth coordinator should not run for demo sign-in")
                return AppSession.LoginResult(backend: backend, account: backend.account)
            },
            demoLoginCoordinator: {
                AppSession.LoginResult(backend: backend, account: backend.account)
            }
        )

        #expect(session.canUseDemoAccount)

        await session.signInWithDemo()

        #expect(session.backend?.account.id == backend.account.id)
        #expect(session.signInError == nil)
    }

    @Test("demo sign-in is hidden when no demo coordinator is provided")
    func demoSignInUnavailableWithoutCoordinator() async {
        let backend = MockBackend()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: InMemoryTokenStore()
        ) {
            AppSession.LoginResult(backend: backend, account: backend.account)
        }

        #expect(!session.canUseDemoAccount)

        await session.signInWithDemo()

        #expect(session.backend == nil)
    }

    @Test("restoreCurrentAccount rebuilds backend for the stored current account")
    func restoreCurrentAccountRebuildsBackend() async {
        let account = BrevAccount(id: "restored", displayName: "Restored", emailAddress: "restored@example.org")
        let backend = MockBackend(account: account)
        let aiBackend = StubAIBackend()
        let session = AppSession(
            accountStore: InMemoryAccountStore(accounts: [account], current: account),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: backend, account: account)
            },
            restoreCoordinator: { restoredAccount in
                #expect(restoredAccount == account)
                return AppSession.LoginResult(
                    backend: backend,
                    account: account,
                    aiBackend: aiBackend
                )
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend?.account == account)
        #expect(session.aiBackend?.identifier == aiBackend.identifier)
        #expect(session.signInError == nil)
        #expect(session.canRetrySessionRestore == false)
    }

    @Test("restoreCurrentAccount persists refined account identity from the restore result")
    func restoreCurrentAccountPersistsRefinedIdentity() async {
        let storedAccount = BrevAccount(
            id: "opaque-user",
            displayName: "Legacy user",
            emailAddress: "unknown@example.org"
        )
        let refinedAccount = BrevAccount(
            id: storedAccount.id,
            displayName: "primary@example.test",
            emailAddress: "primary@example.test"
        )
        let accountStore = InMemoryAccountStore(accounts: [storedAccount], current: storedAccount)
        let backend = MockBackend(account: refinedAccount)
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: backend, account: refinedAccount)
            },
            restoreCoordinator: { restoredAccount in
                #expect(restoredAccount == storedAccount)
                return AppSession.LoginResult(backend: backend, account: refinedAccount)
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend?.account == refinedAccount)
        #expect(await accountStore.accounts == [refinedAccount])
        #expect(await accountStore.current == refinedAccount)
        #expect(session.signInError == nil)
        #expect(session.canRetrySessionRestore == false)
    }

    @Test("interactive sign-in wins over a slow session restore")
    func interactiveSignInWinsOverSlowSessionRestore() async {
        let storedAccount = BrevAccount(id: "stored", displayName: "Stored", emailAddress: "stored@example.org")
        let signedInAccount = BrevAccount(id: "signed-in", displayName: "Signed In", emailAddress: "signed@example.org")
        let restoredBackend = DisconnectTrackingBackend(account: storedAccount)
        let signedInBackend = MockBackend(account: signedInAccount)
        let restoreGate = AsyncGate()
        let session = AppSession(
            accountStore: InMemoryAccountStore(accounts: [storedAccount], current: storedAccount),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                AppSession.LoginResult(backend: signedInBackend, account: signedInAccount)
            },
            restoreCoordinator: { _ in
                await restoreGate.markStarted()
                await restoreGate.waitForResume()
                return AppSession.LoginResult(backend: restoredBackend, account: storedAccount)
            }
        )

        let restoreTask = Task { await session.restoreCurrentAccount() }
        await restoreGate.waitUntilStarted()
        await session.signIn()
        await restoreGate.resume()
        await restoreTask.value

        #expect(session.backend?.account == signedInAccount)
        #expect(await session.accountStore.current == signedInAccount)
        #expect(await restoredBackend.disconnectCount == 1)
    }

    // Note: the scenario "restore coordinator returns no backend" is covered by
    // `restoreCurrentAccountShowsErrorWhenRestoreReturnsNoBackend` below, which
    // asserts the incomplete-settings message. A duplicate test that expected a
    // nil error for the identical setup was removed — it contradicted both that
    // test and the restore implementation.

    @Test("restoreCurrentAccount clears stale account and token when authentication is required")
    func restoreCurrentAccountClearsStaleAuthSession() async {
        let account = BrevAccount(
            id: "stale",
            displayName: "Stale",
            emailAddress: "stale@example.org",
            backendIdentifier: "legacy-backend",
            backendDisplayName: "Legacy backend"
        )
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        let cleanupRecorder = AccountDataCleanupRecorder()
        await tokenStore.setToken(
            Token(
                accessToken: "expired",
                refreshToken: "refresh",
                expiresAt: Date(timeIntervalSince1970: 1)
            ),
            for: account.id
        )
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                throw MailBackendError.authenticationRequired
            },
            accountDataCleanup: { accountID in
                await cleanupRecorder.recordCleanup(accountID)
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend == nil)
        #expect(session.signInError == MailBackendError.authenticationRequired.localizedDescription)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(await tokenStore.token(for: account.id) == nil)
        #expect(await cleanupRecorder.cleanedAccountIDs == [account.id])
        #expect(session.canRetrySessionRestore == false)
    }

    @Test("restoreCurrentAccount preserves IMAP account records when credentials need attention")
    func restoreCurrentAccountPreservesIMAPAccountOnAuthenticationRequired() async {
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        let token = Token(
            accessToken: "local-session",
            refreshToken: "local-session",
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        let cleanupRecorder = AccountDataCleanupRecorder()
        await tokenStore.setToken(token, for: account.id)
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                throw MailBackendError.authenticationRequired
            },
            accountDataCleanup: { accountID in
                await cleanupRecorder.recordCleanup(accountID)
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend == nil)
        #expect(session.signInError == MailBackendError.authenticationRequired.localizedDescription)
        #expect(await accountStore.accounts == [account])
        #expect(await accountStore.current == account)
        #expect(await tokenStore.token(for: account.id) == token)
        #expect(await cleanupRecorder.cleanedAccountIDs.isEmpty)
        #expect(session.canRetrySessionRestore)
    }

    @Test("restoreCurrentAccount treats IMAP authentication failures as credential attention")
    func restoreCurrentAccountTreatsIMAPAuthenticationFailuresAsCredentialAttention() async {
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                throw IMAPClientError.authenticationFailed("A2 NO authentication failed")
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend == nil)
        #expect(session.signInError == "IMAP authentication failed.")
        #expect(session.authFailedIMAPAccountEmail == account.emailAddress)
        #expect(await accountStore.accounts == [account])
        #expect(await accountStore.current == account)
        #expect(session.canRetrySessionRestore)
    }

    @Test("restoreCurrentAccount preserves stored session when restore fails without an auth requirement")
    func restoreCurrentAccountPreservesStoredSessionOnNonAuthFailure() async {
        let account = BrevAccount(id: "retryable", displayName: "Retryable", emailAddress: "retry@example.org")
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        let token = Token(
            accessToken: "expired",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        await tokenStore.setToken(token, for: account.id)
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                throw MailBackendError.backendSpecific(message: "Provider returned an unreadable OAuth token response.")
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend == nil)
        #expect(session.signInError == "Provider returned an unreadable OAuth token response.")
        #expect(await accountStore.accounts == [account])
        #expect(await accountStore.current == account)
        #expect(await tokenStore.token(for: account.id) == token)
        #expect(session.canRetrySessionRestore)
    }

    @Test("restoreCurrentAccount shows an error when restore returns no backend")
    func restoreCurrentAccountShowsErrorWhenRestoreReturnsNoBackend() async {
        let account = BrevAccount(id: "stored", displayName: "Stored", emailAddress: "stored@example.org")
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in nil }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend == nil)
        #expect(session.signInError == "Saved account settings are incomplete. Add the account again or update it in Settings.")
        #expect(await accountStore.accounts == [account])
        #expect(await accountStore.current == account)
        #expect(session.canRetrySessionRestore)
    }

    @Test("restoreAllAccounts treats IMAP authentication failures as credential attention")
    func restoreAllAccountsTreatsIMAPAuthenticationFailuresAsCredentialAttention() async {
        let account = BrevAccount(
            id: "imap-smtp:person@example.org",
            displayName: "Person",
            emailAddress: "person@example.org"
        )
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                throw IMAPClientError.authenticationFailed("A2 NO authentication failed")
            }
        )

        await session.restoreAllAccounts()

        #expect(session.visibleBackends.isEmpty)
        #expect(session.signInError == "IMAP authentication failed.")
        #expect(session.authFailedIMAPAccountEmail == account.emailAddress)
        #expect(session.accountRestoreErrors[account.id] == "IMAP authentication failed.")
        #expect(await accountStore.accounts == [account])
        #expect(await accountStore.current == account)
        #expect(session.canRetrySessionRestore)
    }

    @Test("restoreAllAccounts restores password and OAuth IMAP accounts into workspace")
    func restoreAllAccountsRestoresPasswordAndOAuthIMAPAccountsIntoWorkspace() async {
        let passwordAccount = BrevAccount(
            id: "imap-smtp:password@example.org",
            displayName: "Password",
            emailAddress: "password@example.org"
        )
        let oauthAccount = BrevAccount(
            id: "imap-smtp:person@gmail.com",
            displayName: "Person",
            emailAddress: "person@gmail.com"
        )
        let passwordBackend = MockBackend(account: passwordAccount)
        let oauthBackend = MockBackend(account: oauthAccount)
        let accountStore = InMemoryAccountStore(
            accounts: [passwordAccount, oauthAccount],
            current: oauthAccount
        )
        var restoredAccountIDs: [BrevAccount.ID] = []
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: passwordAccount), account: passwordAccount)
            },
            restoreCoordinator: { account in
                restoredAccountIDs.append(account.id)
                if account.id == passwordAccount.id {
                    return AppSession.LoginResult(backend: passwordBackend, account: passwordAccount)
                }
                if account.id == oauthAccount.id {
                    return AppSession.LoginResult(backend: oauthBackend, account: oauthAccount)
                }
                return nil
            }
        )

        await session.restoreAllAccounts()

        // Preferred/current account restores first for usable startup, then others.
        #expect(restoredAccountIDs.first == oauthAccount.id)
        #expect(Set(restoredAccountIDs) == Set([passwordAccount.id, oauthAccount.id]))
        #expect(session.backend?.account == oauthAccount)
        #expect(session.visibleBackends.map { $0.account.id } == [
            "imap-smtp:password@example.org",
            "imap-smtp:person@gmail.com",
        ])
        #expect(session.accountRestoreErrors.isEmpty)
        #expect(session.signInError == nil)
        #expect(await accountStore.current == oauthAccount)
    }

    @Test("restoreAllAccounts promotes secondary when preferred account fails")
    func restoreAllAccountsPromotesSecondaryWhenPreferredFails() async {
        let secondary = BrevAccount(
            id: "imap-smtp:secondary@example.org",
            displayName: "Secondary",
            emailAddress: "secondary@example.org"
        )
        let preferred = BrevAccount(
            id: "imap-smtp:preferred@example.org",
            displayName: "Preferred",
            emailAddress: "preferred@example.org"
        )
        let secondaryBackend = MockBackend(account: secondary)
        let accountStore = InMemoryAccountStore(
            accounts: [secondary, preferred],
            current: preferred
        )
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            restoreCoordinator: { account in
                if account.id == preferred.id {
                    throw IMAPClientError.authenticationFailed("NO bad password")
                }
                if account.id == secondary.id {
                    return AppSession.LoginResult(backend: secondaryBackend, account: secondary)
                }
                return nil
            }
        )

        await session.restoreAllAccounts()

        #expect(session.backend?.account == secondary)
        #expect(session.accountRestoreErrors[preferred.id] != nil)
        #expect(await accountStore.current == secondary)
    }

    @Test("restoreAllAccounts restores current account before secondary accounts")
    func restoreAllAccountsRestoresCurrentAccountBeforeSecondaryAccounts() async {
        let secondary = BrevAccount(
            id: "imap-smtp:secondary@example.org",
            displayName: "Secondary",
            emailAddress: "secondary@example.org"
        )
        let current = BrevAccount(
            id: "imap-smtp:current@example.org",
            displayName: "Current",
            emailAddress: "current@example.org"
        )
        let secondaryBackend = MockBackend(account: secondary)
        let currentBackend = MockBackend(account: current)
        let accountStore = InMemoryAccountStore(
            accounts: [secondary, current],
            current: current
        )
        var restoredAccountIDs: [BrevAccount.ID] = []
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            restoreCoordinator: { account in
                restoredAccountIDs.append(account.id)
                if account.id == secondary.id {
                    return AppSession.LoginResult(backend: secondaryBackend, account: secondary)
                }
                if account.id == current.id {
                    return AppSession.LoginResult(backend: currentBackend, account: current)
                }
                return nil
            }
        )

        await session.restoreAllAccounts()

        #expect(restoredAccountIDs.first == current.id)
        #expect(session.backend?.account == current)
        #expect(await accountStore.current == current)
    }

    @Test("CardDAV contact sync starts only when OAuth bearer token is available")
    func cardDAVContactSyncStartsOnlyWhenOAuthBearerTokenIsAvailable() async {
        let passwordAccount = BrevAccount(
            id: "imap-smtp:password@example.org",
            displayName: "Password",
            emailAddress: "password@example.org"
        )
        let oauthAccount = BrevAccount(
            id: "imap-smtp:oauth@example.org",
            displayName: "OAuth",
            emailAddress: "oauth@example.org"
        )
        let passwordBackend = CardDAVSyncSupportingBackend(
            account: passwordAccount,
            bearerToken: nil
        )
        let oauthBackend = CardDAVSyncSupportingBackend(
            account: oauthAccount,
            bearerToken: "oauth-token"
        )
        let accountStore = InMemoryAccountStore(
            accounts: [passwordAccount, oauthAccount],
            current: oauthAccount
        )
        var syncStarts: [(email: String, host: String?, token: String)] = []
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            restoreCoordinator: { account in
                if account.id == passwordAccount.id {
                    return AppSession.LoginResult(backend: passwordBackend, account: passwordAccount)
                }
                if account.id == oauthAccount.id {
                    return AppSession.LoginResult(backend: oauthBackend, account: oauthAccount)
                }
                return nil
            },
            cardDAVContactSyncStarter: { _, configuration, token in
                syncStarts.append((
                    email: configuration.email,
                    host: configuration.principalURL.host,
                    token: token
                ))
            }
        )

        await session.restoreAllAccounts()

        #expect(syncStarts.count == 1)
        #expect(syncStarts.first?.email == "oauth@example.org")
        #expect(syncStarts.first?.host == "example.org")
        #expect(syncStarts.first?.token == "oauth-token")
        #expect(!passwordBackend.contactLookupProviderWasSet)
        #expect(oauthBackend.contactLookupProviderWasSet)
    }

    @Test("restoreAllAccounts shows an error when restore returns no backend")
    func restoreAllAccountsShowsErrorWhenRestoreReturnsNoBackend() async {
        let account = BrevAccount(id: "stored", displayName: "Stored", emailAddress: "stored@example.org")
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in nil }
        )

        await session.restoreAllAccounts()

        #expect(session.visibleBackends.isEmpty)
        #expect(session.signInError == "Saved account settings are incomplete. Add the account again or update it in Settings.")
        #expect(session
            .accountRestoreErrors[account.id] ==
            "Saved account settings are incomplete. Add the account again or update it in Settings.")
        #expect(await accountStore.accounts == [account])
        #expect(await accountStore.current == account)
        #expect(session.canRetrySessionRestore)
    }

    @Test("restoreCurrentAccount can retry a preserved stored session after a transient failure")
    func restoreCurrentAccountRetriesAfterTransientFailure() async {
        let account = BrevAccount(id: "retryable", displayName: "Retryable", emailAddress: "retry@example.org")
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        let token = Token(
            accessToken: "expired",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        await tokenStore.setToken(token, for: account.id)
        let restoredBackend = MockBackend(account: account)
        var restoreAttempts = 0
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore retry")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                restoreAttempts += 1
                if restoreAttempts == 1 {
                    throw MailBackendError.network(underlying: "timed out")
                }
                return AppSession.LoginResult(backend: restoredBackend, account: account)
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.backend == nil)
        #expect(session.canRetrySessionRestore)
        #expect(await tokenStore.token(for: account.id) == token)

        await session.restoreCurrentAccount()

        #expect(restoreAttempts == 2)
        #expect(session.backend?.account == account)
        #expect(session.signInError == nil)
        #expect(session.canRetrySessionRestore == false)
        #expect(await accountStore.current == account)
        #expect(await tokenStore.token(for: account.id) == token)
    }

    @Test("restoreCurrentAccount uses a fallback message when the restore error description is blank")
    func restoreCurrentAccountUsesFallbackMessageForBlankRestoreError() async {
        let account = BrevAccount(id: "blank-restore", displayName: "Blank", emailAddress: "blank@example.org")
        let session = AppSession(
            accountStore: InMemoryAccountStore(accounts: [account], current: account),
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                throw NSError(domain: "BrevTests", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])
            }
        )

        await session.restoreCurrentAccount()

        #expect(session.signInError == "Couldn't restore your session.")
    }

    @Test("signOut(account:) clears a stored account and token without an active backend")
    func signOutSelectedStoredAccountWithoutActiveBackend() async {
        let account = BrevAccount(id: "stored", displayName: "Stored", emailAddress: "stored@example.org")
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        await tokenStore.setToken(
            Token(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date(timeIntervalSinceNow: 3600)
            ),
            for: account.id
        )
        var signedOutAccounts: [BrevAccount] = []
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during sign out")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            signOutCoordinator: { signedOutAccounts.append($0) }
        )

        await session.signOut(account: account)

        #expect(session.backend == nil)
        #expect(session.aiBackend == nil)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(await tokenStore.token(for: account.id) == nil)
        #expect(signedOutAccounts == [account])
    }

    @Test("duplicate signOut(account:) requests for the same account are ignored")
    func duplicateSignOutRequestsForSameAccountAreIgnored() async {
        let account = BrevAccount(
            id: "stored",
            displayName: "Stored",
            emailAddress: "stored@example.org"
        )
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let signOutGate = AsyncGate()
        var signOutAttempts = 0
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during sign out")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            signOutCoordinator: { _ in
                signOutAttempts += 1
                if signOutAttempts == 1 {
                    await signOutGate.markStarted()
                    await signOutGate.waitForResume()
                }
            }
        )

        let firstSignOut = Task { await session.signOut(account: account) }
        await signOutGate.waitUntilStarted()
        await session.signOut(account: account)

        #expect(signOutAttempts == 1)

        await signOutGate.resume()
        await firstSignOut.value
    }

    @Test("restoreCurrentAccount does not restart an account while sign-out is pending")
    func restoreCurrentAccountDoesNotRestartAccountWhileSignOutIsPending() async {
        let account = BrevAccount(
            id: "active",
            displayName: "Active",
            emailAddress: "active@example.org"
        )
        let activeBackend = DisconnectTrackingBackend(account: account)
        let restoredBackend = DisconnectTrackingBackend(account: account)
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        await tokenStore.setToken(
            Token(
                accessToken: "active-access",
                refreshToken: "active-refresh",
                expiresAt: Date(timeIntervalSinceNow: 3600)
            ),
            for: account.id
        )
        let signOutGate = AsyncGate()
        var restoreAttempts = 0
        let session = AppSession(
            backend: activeBackend,
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during sign out")
                return AppSession.LoginResult(backend: restoredBackend, account: account)
            },
            restoreCoordinator: { _ in
                restoreAttempts += 1
                return AppSession.LoginResult(backend: restoredBackend, account: account)
            },
            signOutCoordinator: { _ in
                await signOutGate.markStarted()
                await signOutGate.waitForResume()
            }
        )

        let signOutTask = Task { await session.signOut(account: account) }
        await signOutGate.waitUntilStarted()

        await session.restoreCurrentAccount()

        #expect(restoreAttempts == 0)

        await signOutGate.resume()
        await signOutTask.value

        #expect(session.backend == nil)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(await tokenStore.token(for: account.id) == nil)
    }

    @Test("interactive sign-in does not start while sign-out is pending")
    func interactiveSignInDoesNotStartWhileSignOutIsPending() async {
        let activeAccount = BrevAccount(
            id: "active",
            displayName: "Active",
            emailAddress: "active@example.org"
        )
        let interactiveAccount = BrevAccount(
            id: "interactive",
            displayName: "Interactive",
            emailAddress: "interactive@example.org"
        )
        let activeBackend = DisconnectTrackingBackend(account: activeAccount)
        let interactiveBackend = DisconnectTrackingBackend(account: interactiveAccount)
        let accountStore = InMemoryAccountStore(accounts: [activeAccount], current: activeAccount)
        let signOutGate = AsyncGate()
        var loginAttempts = 0
        let session = AppSession(
            backend: activeBackend,
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                loginAttempts += 1
                return AppSession.LoginResult(backend: interactiveBackend, account: interactiveAccount)
            },
            signOutCoordinator: { _ in
                await signOutGate.markStarted()
                await signOutGate.waitForResume()
            }
        )

        let signOutTask = Task { await session.signOut(account: activeAccount) }
        await signOutGate.waitUntilStarted()

        await session.signIn()

        #expect(loginAttempts == 0)

        await signOutGate.resume()
        await signOutTask.value

        #expect(session.backend == nil)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
    }

    @Test("demo sign-in does not start while sign-out is pending")
    func demoSignInDoesNotStartWhileSignOutIsPending() async {
        let activeAccount = BrevAccount(
            id: "active",
            displayName: "Active",
            emailAddress: "active@example.org"
        )
        let demoAccount = BrevAccount(
            id: "demo",
            displayName: "Demo",
            emailAddress: "demo@example.org"
        )
        let activeBackend = DisconnectTrackingBackend(account: activeAccount)
        let demoBackend = DisconnectTrackingBackend(account: demoAccount)
        let accountStore = InMemoryAccountStore(accounts: [activeAccount], current: activeAccount)
        let signOutGate = AsyncGate()
        var demoAttempts = 0
        let session = AppSession(
            backend: activeBackend,
            accountStore: accountStore,
            tokenStore: InMemoryTokenStore(),
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during demo sign-in test")
                return AppSession.LoginResult(backend: demoBackend, account: demoAccount)
            },
            demoLoginCoordinator: {
                demoAttempts += 1
                return AppSession.LoginResult(backend: demoBackend, account: demoAccount)
            },
            signOutCoordinator: { _ in
                await signOutGate.markStarted()
                await signOutGate.waitForResume()
            }
        )

        let signOutTask = Task { await session.signOut(account: activeAccount) }
        await signOutGate.waitUntilStarted()

        await session.signInWithDemo()

        #expect(demoAttempts == 0)

        await signOutGate.resume()
        await signOutTask.value

        #expect(session.backend == nil)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
    }

    @Test("signOut(account:) restores the next saved account after signing out the active account")
    func signOutActiveAccountRestoresNextSavedAccount() async {
        let activeAccount = BrevAccount(
            id: "active",
            displayName: "Active",
            emailAddress: "active@example.org"
        )
        let nextAccount = BrevAccount(
            id: "next",
            displayName: "Next",
            emailAddress: "next@example.org"
        )
        let activeBackend = DisconnectTrackingBackend(account: activeAccount)
        let nextBackend = MockBackend(account: nextAccount)
        let accountStore = InMemoryAccountStore(
            accounts: [activeAccount, nextAccount],
            current: activeAccount
        )
        let tokenStore = InMemoryTokenStore()
        let nextToken = Token(
            accessToken: "next-access",
            refreshToken: "next-refresh",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        await tokenStore.setToken(
            Token(
                accessToken: "active-access",
                refreshToken: "active-refresh",
                expiresAt: Date(timeIntervalSinceNow: 3600)
            ),
            for: activeAccount.id
        )
        await tokenStore.setToken(nextToken, for: nextAccount.id)
        var restoreAttempts = 0
        let session = AppSession(
            backend: activeBackend,
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during sign out fallback")
                return AppSession.LoginResult(backend: nextBackend, account: nextAccount)
            },
            restoreCoordinator: { account in
                restoreAttempts += 1
                #expect(account == nextAccount)
                return AppSession.LoginResult(backend: nextBackend, account: nextAccount)
            }
        )

        await session.signOut(account: activeAccount)

        #expect(await activeBackend.disconnectCount == 1)
        #expect(session.backend?.account == nextAccount)
        #expect(await accountStore.accounts == [nextAccount])
        #expect(await accountStore.current == nextAccount)
        #expect(await tokenStore.token(for: activeAccount.id) == nil)
        #expect(await tokenStore.token(for: nextAccount.id) == nextToken)
        #expect(restoreAttempts == 1)
        #expect(session.signInError == nil)
        #expect(session.canRetrySessionRestore == false)
    }

    @Test("signOut(account:) clears stale restore error state")
    func signOutSelectedStoredAccountClearsStaleRestoreErrorState() async {
        let account = BrevAccount(id: "retryable", displayName: "Retryable", emailAddress: "retry@example.org")
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        await tokenStore.setToken(
            Token(
                accessToken: "expired",
                refreshToken: "refresh",
                expiresAt: Date(timeIntervalSince1970: 1)
            ),
            for: account.id
        )
        let session = AppSession(
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during restore")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            restoreCoordinator: { _ in
                throw MailBackendError.network(underlying: "offline")
            }
        )

        await session.restoreCurrentAccount()
        #expect(session.signInError == "Network error: offline")
        #expect(session.canRetrySessionRestore)

        await session.signOut(account: account)

        #expect(session.signInError == nil)
        #expect(session.canRetrySessionRestore == false)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(await tokenStore.token(for: account.id) == nil)
    }

    @Test("signOut(account:) clears pending offline mutation queue for that account")
    func signOutClearsPendingOfflineMutationQueueForAccount() async throws {
        let account = BrevAccount(id: "queued-account", displayName: "Queued", emailAddress: "queued@example.org")
        let queueDefaultsSuite = "brev.offline-queue.\(UUID().uuidString)"
        let queueDefaults = try #require(UserDefaults(suiteName: queueDefaultsSuite))
        queueDefaults.removePersistentDomain(forName: queueDefaultsSuite)
        let queue = OfflineMutationQueueStorage.queue(
            accountID: account.id,
            defaults: queueDefaults
        )
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["msg-1"]))
        #expect(try await queue.pending().count == 1)

        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        await tokenStore.setToken(
            Token(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date(timeIntervalSinceNow: 3600)
            ),
            for: account.id
        )

        let session = AppSession(
            backend: MockBackend(account: account),
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during sign out")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            pendingMutationCleanup: { accountID in
                await OfflineMutationQueueStorage.clearPendingMutations(
                    for: accountID,
                    defaults: queueDefaults
                )
            }
        )

        await session.signOut(account: account)
        let reopened = OfflineMutationQueueStorage.queue(
            accountID: account.id,
            defaults: queueDefaults
        )
        #expect(try await reopened.pending().isEmpty)
    }

    @Test("removeAccount clears local account state and runs provider sign-out")
    func removeAccountClearsLocalAccountStateAndRunsProviderSignOut() async throws {
        let account = BrevAccount(id: "remove-local", displayName: "Remove", emailAddress: "remove@example.org")
        let accountStore = InMemoryAccountStore(accounts: [account], current: account)
        let tokenStore = InMemoryTokenStore()
        await tokenStore.setToken(
            Token(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date(timeIntervalSinceNow: 3600)
            ),
            for: account.id
        )
        let queueDefaultsSuite = "brev.remove-account.\(UUID().uuidString)"
        let queueDefaults = try #require(UserDefaults(suiteName: queueDefaultsSuite))
        queueDefaults.removePersistentDomain(forName: queueDefaultsSuite)
        let queue = OfflineMutationQueueStorage.queue(
            accountID: account.id,
            defaults: queueDefaults
        )
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["msg-1"]))
        var signOutCoordinatorCalls = 0
        let removedSource = MailSourceID(accountID: account.id, mailboxID: "personal")
        let keptSource = MailSourceID(accountID: "kept-account", mailboxID: "work")
        let now = Date(timeIntervalSince1970: 1000)
        let removedMessage = SourceMessageID(sourceID: removedSource, messageID: "remove-me")
        let keptMessage = SourceMessageID(sourceID: keptSource, messageID: "keep-me")
        MailboxSourcePreferencesStorage.save(MailboxSourcePreferences(
            enabledSourceIDs: [removedSource, keptSource],
            defaultSourceID: removedSource
        ))
        FolderVisibilityPreferencesStorage.save(FolderVisibilityPreferences(hiddenFolderIDs: [
            SourceFolderID(sourceID: removedSource, folderID: "archive"),
            SourceFolderID(sourceID: keptSource, folderID: "archive")
        ]))
        FolderAliasPreferencesStorage.save(FolderAliasPreferences(aliases: [
            FolderAliasPreference(
                folderID: SourceFolderID(sourceID: removedSource, folderID: "inbox"),
                name: "Home"
            ),
            FolderAliasPreference(
                folderID: SourceFolderID(sourceID: keptSource, folderID: "inbox"),
                name: "Work"
            )
        ]))
        LocalMessageWorkflowStateStorage.save(
            LocalMessageWorkflowStatePolicy.markingDone(
                [removedMessage, keptMessage],
                now: now,
                in: LocalMessageWorkflowStatePolicy.snoozing(
                    removedMessage,
                    until: now.addingTimeInterval(3600),
                    now: now,
                    in: .defaults
                )
            )
        )
        defer {
            UserDefaults.standard.removeObject(forKey: MailboxSourcePreferencesStorage.storageKey)
            UserDefaults.standard.removeObject(forKey: FolderVisibilityPreferencesStorage.storageKey)
            UserDefaults.standard.removeObject(forKey: FolderAliasPreferencesStorage.storageKey)
            UserDefaults.standard.removeObject(forKey: LocalMessageWorkflowStateStorage.storageKey)
        }

        let session = AppSession(
            backend: DisconnectTrackingBackend(account: account),
            accountStore: accountStore,
            tokenStore: tokenStore,
            loginCoordinator: {
                Issue.record("Interactive sign-in should not run during account removal")
                return AppSession.LoginResult(backend: MockBackend(account: account), account: account)
            },
            signOutCoordinator: { _ in signOutCoordinatorCalls += 1 },
            pendingMutationCleanup: { accountID in
                await OfflineMutationQueueStorage.clearPendingMutations(
                    for: accountID,
                    defaults: queueDefaults
                )
            }
        )

        await session.removeAccount(account)

        #expect(signOutCoordinatorCalls == 1)
        #expect(session.backend == nil)
        #expect(session.aiBackend == nil)
        #expect(await accountStore.accounts.isEmpty)
        #expect(await accountStore.current == nil)
        #expect(await tokenStore.token(for: account.id) == nil)
        let reopened = OfflineMutationQueueStorage.queue(
            accountID: account.id,
            defaults: queueDefaults
        )
        #expect(try await reopened.pending().isEmpty)
        #expect(MailboxSourcePreferencesStorage.load() == MailboxSourcePreferences(
            enabledSourceIDs: [keptSource],
            defaultSourceID: nil
        ))
        #expect(FolderVisibilityPreferencesStorage.load() == FolderVisibilityPreferences(
            hiddenFolderIDs: [SourceFolderID(sourceID: keptSource, folderID: "archive")]
        ))
        #expect(FolderAliasPreferencesStorage.load() == FolderAliasPreferences(aliases: [
            FolderAliasPreference(
                folderID: SourceFolderID(sourceID: keptSource, folderID: "inbox"),
                name: "Work"
            )
        ]))
        #expect(LocalMessageWorkflowStateStorage.load() == LocalMessageWorkflowState(
            snoozes: [],
            doneMessages: [
                LocalMessageDone(messageID: keptMessage, completedAt: now)
            ]
        ))
    }

    @Test("refreshing configured AI providers updates the active account route")
    func refreshingConfiguredAIProvidersUpdatesActiveAccountRoute() async throws {
        let defaults = try Self.makeAIProviderDefaults()
        let configuration = try #require(AIProviderConfiguration(
            id: AIProviderID("private-gateway"),
            kind: .customOpenAICompatible,
            displayName: "Private Gateway",
            endpointURL: URL(string: "https://ai.example.test/v1"),
            modelID: "mail-model",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        try AIProviderConfigurationStore(defaults: defaults).save([configuration])
        let secrets = InMemoryAIProviderSecretStore()
        try await secrets.setAPIKey("test-key", for: configuration.id)
        let backend = MockBackend()
        let session = AppSession(
            backend: backend,
            accountStore: InMemoryAccountStore(accounts: [backend.account], current: backend.account),
            tokenStore: InMemoryTokenStore(),
            aiProviderBackendResolver: AIProviderBackendResolver(
                defaults: defaults,
                secretStore: secrets
            )
        )

        await session.reloadConfiguredAIBackends()

        #expect(session.aiBackends[backend.account.id]?.displayName == "Private Gateway")
        #expect(session.aiBackend?.transparencyLabel == "Sent to: Private Gateway (ai.example.test)")
    }

    private static func makeAIProviderDefaults() throws -> UserDefaults {
        let suiteName = "AppSessionAIProviderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor AccountDataCleanupRecorder {
    private(set) var signOutCalls = 0
    private(set) var cleanedAccountIDs: [BrevAccount.ID] = []

    func recordSignOut() {
        signOutCalls += 1
    }

    func recordCleanup(_ accountID: BrevAccount.ID) {
        cleanedAccountIDs.append(accountID)
    }
}

private actor InMemoryTokenStore: TokenStore {
    private var tokens: [String: Token] = [:]

    func token(for accountID: String) -> Token? {
        tokens[accountID]
    }

    func setToken(_ token: Token, for accountID: String) {
        tokens[accountID] = token
    }

    func clearToken(for accountID: String) {
        tokens[accountID] = nil
    }
}

private class DisconnectTrackingBackend: MailBackend, @unchecked Sendable {
    let account: BrevAccount
    let capabilities: BackendCapabilities = []
    private let state = DisconnectTrackingState()

    init(account: BrevAccount) {
        self.account = account
    }

    var disconnectCount: Int {
        get async { await state.disconnectCount }
    }

    func connect() async throws {}

    func disconnect() async {
        await state.incrementDisconnectCount()
    }

    func folders() async throws -> [Folder] { [] }

    func refresh(folder _: Folder) async throws {}

    func messages(in _: Folder, pageToken _: String?) async throws -> (
        headers: [MessageHeader],
        nextPageToken: String?
    ) {
        ([], nil)
    }

    func body(for messageID: String) async throws -> MessageBody {
        MessageBody(messageID: messageID)
    }

    func setRead(_: Bool, for _: [String]) async throws {}

    func setFlagged(_: Bool, for _: [String]) async throws {}

    func move(messageIDs _: [String], to _: Folder) async throws {}

    func delete(messageIDs _: [String]) async throws {}

    func save(draft: Draft) async throws -> Draft {
        draft
    }

    func discard(draftID _: String) async throws {}

    func send(draft _: Draft) async throws -> SendResult {
        SendResult(sentMessageID: "sent")
    }

    func search(_: SearchQuery) async throws -> [MessageHeader] {
        []
    }

    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        CalendarEvent(
            id: attachmentID,
            title: "Event",
            start: Date(),
            end: Date(),
            location: nil,
            organizer: nil,
            attendees: [],
            description: nil
        )
    }

    func replyToCalendarInvite(messageID _: String, response _: AttendeeState) async throws {}

    func subscribeToChanges() -> AsyncStream<MailEvent> {
        AsyncStream { $0.finish() }
    }
}

private final class CardDAVSyncSupportingBackend: DisconnectTrackingBackend, CardDAVContactSyncSupporting, @unchecked Sendable {
    private let bearerToken: String?
    private(set) var contactLookupProviderWasSet = false

    init(account: BrevAccount, bearerToken: String?) {
        self.bearerToken = bearerToken
        super.init(account: account)
    }

    var emailAddressForCardDAV: String {
        account.emailAddress
    }

    var bearerTokenForCardDAV: String? {
        bearerToken
    }

    func setContactLookupProvider(_: (any ContactLookupProviding)?) {
        contactLookupProviderWasSet = true
    }
}

private actor DisconnectTrackingState {
    private(set) var disconnectCount = 0

    func incrementDisconnectCount() {
        disconnectCount += 1
    }
}

private actor AsyncGate {
    private var hasStarted = false
    private var shouldResume = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func waitForResume() async {
        if shouldResume { return }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func resume() {
        shouldResume = true
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private struct StubAIBackend: AIBackend {
    let identifier: String
    let displayName: String
    let transparencyLabel: String

    init(identifier: String = "stub-ai") {
        self.identifier = identifier
        displayName = "Stub AI"
        transparencyLabel = "Sent to: Stub AI"
    }

    func generateReply(to _: [AIMessage], instruction _: String?) async throws -> AIResponse {
        AIResponse(text: "")
    }

    func shortcut(_: AIShortcutAction, on text: String) async throws -> AIResponse {
        AIResponse(text: text)
    }
}

private actor InMemoryAIProviderSecretStore: AIProviderSecretStore {
    private var keys: [AIProviderID: String] = [:]

    func apiKey(for providerID: AIProviderID) async throws -> String? {
        keys[providerID]
    }

    func setAPIKey(_ apiKey: String, for providerID: AIProviderID) async throws {
        keys[providerID] = apiKey
    }

    func deleteAPIKey(for providerID: AIProviderID) async throws {
        keys[providerID] = nil
    }
}

private struct NativeSetupFallbackError: Error, Sendable, IMAPFallbackEligibleError {
    var isIMAPFallbackEligible: Bool { true }
}
