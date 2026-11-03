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
import BrevMail
import Foundation
import Testing

#if DEBUG
@Suite("Isolated mock session")
@MainActor
struct IsolatedMockSessionTests {
    @Test("Bootstrap and sign-in stay synthetic without production services")
    func mockOnlyWiring() async throws {
        let suite = "IsolatedMockSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionFactory.makeIsolatedMock(themeDefaults: defaults)
        let backend = try #require(session.backend)
        #expect(backend is MockBackend)
        #expect(session.accountStore is InMemoryAccountStore)
        #expect(!(session.tokenStore is KeychainTokenStore))
        #expect(await session.accountStore.current?.id == backend.account.id)
        #expect(session.localBackend == nil)
        #expect(session.pimSourceCoordinator == nil)
        #expect(session.googleDriveFeature == nil)
        #expect(!session.canUseIMAPAccountSetup)
        #expect(!session.canValidateIMAPAccountSetup)
        #expect(!session.canUseIMAPOAuthSetup)
        #expect(!session.canStartIMAPOAuthBrowserSetup)
        #expect(!session.canStartGoogleSignIn)
        #expect(!session.canStartNativeGoogleSignIn)
        #expect(!session.canDiscoverIMAPSettings)
        await session.restoreAllAccounts()
        #expect(session.backend?.account.id == backend.account.id)
        await session.signOut(account: backend.account)
        await session.signIn()
        #expect(session.backend?.account.id == backend.account.id)
        #expect(session.visibleBackends.count == 1)
    }
}
#endif
