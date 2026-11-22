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
    #if !DEBUG
    @Test("release builds ignore injected demo requests")
    func releaseBuildIgnoresInjectedDemoRequest() {
        let configuration = AppSessionFactory.Configuration(
            applicationSupportURL: URL(filePath: "/tmp/brev-app-session-factory-release-tests"),
            oauthPresentationAnchor: { fatalError("OAuth anchor is not needed in this wiring test") },
            isDemoModeRequested: { true }
        )

        let session = AppSessionFactory.makeDefault(configuration: configuration)

        #expect(session.backend == nil)
        #expect(!session.canUseDemoAccount)
    }
    #endif

    #if DEBUG
    @Test("developer demo policy builds the same usable session for either app target")
    func demoPolicyBuildsDemoSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSessionDemoJournal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let demo = MockBackend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
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

        let mailbox = try await demo.currentMailbox()
        _ = try await demo.send(
            draft: Draft(id: "demo-remove", scheduledFor: Date(timeIntervalSince1970: 2_000_000_000)),
            sourceID: demo.sourceID(for: mailbox)
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
        await session.removeAccount(demo.account)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("ordinary demo login registers its persistent Mock for account cleanup")
    func demoLoginRegistersMockForCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSessionDemoLoginJournal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let demo = MockBackend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let configuration = AppSessionFactory.Configuration(
            applicationSupportURL: URL(filePath: "/tmp/brev-app-session-factory-tests"),
            oauthPresentationAnchor: { fatalError("OAuth anchor is not needed in demo mode") },
            isDemoModeRequested: { false },
            makeDemoBackend: { demo }
        )
        let session = AppSessionFactory.makeDefault(configuration: configuration)

        await session.signInWithDemo()
        #expect(session.backend?.account.id == demo.account.id)
        let mailbox = try await demo.currentMailbox()
        _ = try await demo.send(
            draft: Draft(id: "ordinary-demo-remove", scheduledFor: Date(timeIntervalSince1970: 2_000_000_000)),
            sourceID: demo.sourceID(for: mailbox)
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)

        await session.removeAccount(demo.account)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    #endif

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
