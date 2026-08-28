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

import BrevBackend
import BrevMail
import Foundation
import Testing

@Suite("AppSessionFactory")
@MainActor
struct AppSessionFactoryTests {
    @Test("demo policy builds the same usable demo session for either app target")
    func demoPolicyBuildsDemoSession() async {
        let demo = MockBackend()
        let configuration = AppSessionFactory.Configuration(
            applicationSupportURL: URL(filePath: "/tmp/brev-app-session-factory-tests"),
            oauthPresentationAnchor: { fatalError("OAuth anchor is not needed in demo mode") },
            isDemoModeRequested: { true },
            makeDemoBackend: { demo }
        )

        let session = AppSessionFactory.makeDefault(configuration: configuration)

        #expect(session.backend?.account.id == demo.account.id)
        #expect(await session.accountStore.current == demo.account)
        #expect(!session.canUseDemoAccount)
        #expect(session.canUseInteractiveSignIn)
    }

    @Test("production policy wires every account setup and restore coordinator")
    func productionPolicyWiresAccountCoordinators() {
        let configuration = AppSessionFactory.Configuration(
            applicationSupportURL: URL(filePath: "/tmp/brev-app-session-factory-tests"),
            oauthPresentationAnchor: { fatalError("OAuth anchor is not needed in this wiring test") },
            isDemoModeRequested: { false }
        )

        let session = AppSessionFactory.makeDefault(configuration: configuration)

        #expect(session.backend == nil)
        #expect(session.canUseIMAPAccountSetup)
        #expect(session.canValidateIMAPAccountSetup)
        #expect(session.canUseIMAPOAuthSetup)
        #expect(session.canStartIMAPOAuthBrowserSetup)
        #expect(session.canDiscoverIMAPSettings)
    }

    @Test("missing Gmail removal wiring fails closed and retains the account")
    func missingGmailRemovalCoordinatorRetainsAccount() async {
        let configuration = AppSessionFactory.Configuration(
            applicationSupportURL: URL(filePath: "/tmp/brev-app-session-factory-tests"),
            oauthPresentationAnchor: { fatalError("OAuth anchor is not needed in this wiring test") },
            isDemoModeRequested: { false }
        )
        let session = AppSessionFactory.makeDefault(configuration: configuration)
        let account = BrevAccount(
            id: "gmail-api:missing-removal-\(UUID().uuidString)",
            displayName: "Gmail",
            emailAddress: "gmail@example.com",
            backendIdentifier: BrevAccount.gmailAPIBackendIdentifier,
            backendDisplayName: BrevAccount.gmailAPIBackendDisplayName
        )
        await session.accountStore.add(account)

        await session.removeAccount(account)

        #expect(await session.accountStore.accounts.contains(account))
        await session.accountStore.remove(account.id)
    }
}
