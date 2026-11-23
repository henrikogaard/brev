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
    }

    @Test("factory-owned demo lifecycle reconnects and cleans up after relogin")
    func demoLoginRegistersMockForCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSessionDemoLoginJournal-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "AppSessionDemoLoginDefaults-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = AppSessionFactory.makeIsolatedMock(themeDefaults: defaults, mockPersistenceDirectory: directory)

        await session.signInWithDemo()
        let first = try #require(session.backend as? MockBackend)
        #expect(session.backend?.account.id == first.account.id)
        let mailbox = try await first.currentMailbox()
        _ = try await first.send(
            draft: Draft(id: "ordinary-demo-remove", scheduledFor: Date(timeIntervalSince1970: 2_000_000_000)),
            sourceID: first.sourceID(for: mailbox)
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)

        await session.removeAccount(first.account)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await #expect(throws: (any Error).self) {
            try await first.send(draft: Draft(id: "late-send"), sourceID: first.sourceID(for: mailbox))
        }

        await session.signInWithDemo()
        let second = try #require(session.backend as? MockBackend)
        #expect(ObjectIdentifier(second) != ObjectIdentifier(first))
        let secondMailbox = try await second.currentMailbox()
        _ = try await second.send(
            draft: Draft(id: "fresh-after-relogin", scheduledFor: .distantPast),
            sourceID: second.sourceID(for: secondMailbox)
        )
        await second.deliverDueScheduledSends()
        #expect(second.pendingScheduledSends().isEmpty)
        await session.removeAccount(second.account)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("demo login reports a Mock connection failure")
    func demoLoginReportsMockConnectionFailure() async throws {
        let journalPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSessionDemoJournalFile-\(UUID().uuidString)")
        try Data([1]).write(to: journalPath)
        defer { try? FileManager.default.removeItem(at: journalPath) }
        let suiteName = "AppSessionDemoFailureDefaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = AppSessionFactory.makeIsolatedMock(
            themeDefaults: defaults,
            mockPersistenceDirectory: journalPath
        )
        let initial = try #require(session.backend as? MockBackend)

        await session.signInWithDemo()

        #expect(session.signInError != nil)
        #expect(!session.isSigningIn)
        let active = try #require(session.backend as? MockBackend)
        #expect(ObjectIdentifier(active) == ObjectIdentifier(initial))

        try FileManager.default.removeItem(at: journalPath)
        await session.removeAccount(initial.account)
    }

    @Test("same-account demo sessions clean only their own persistence directories")
    func demoCleanupIsPerSession() async throws {
        let firstDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSessionDemoJournalA-\(UUID().uuidString)", isDirectory: true)
        let secondDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSessionDemoJournalB-\(UUID().uuidString)", isDirectory: true)
        let firstSuite = "AppSessionDemoDefaultsA-\(UUID().uuidString)"
        let secondSuite = "AppSessionDemoDefaultsB-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
        let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        let firstSession = AppSessionFactory.makeIsolatedMock(
            themeDefaults: firstDefaults,
            mockPersistenceDirectory: firstDirectory
        )
        let secondSession = AppSessionFactory.makeIsolatedMock(
            themeDefaults: secondDefaults,
            mockPersistenceDirectory: secondDirectory
        )
        let first = try #require(firstSession.backend as? MockBackend)
        let second = try #require(secondSession.backend as? MockBackend)
        #expect(first.account.id == second.account.id)
        let firstMailbox = try await first.currentMailbox()
        let secondMailbox = try await second.currentMailbox()
        _ = try await first.send(
            draft: Draft(id: "session-a", scheduledFor: Date(timeIntervalSince1970: 2_000_000_000)),
            sourceID: first.sourceID(for: firstMailbox)
        )
        _ = try await second.send(
            draft: Draft(id: "session-b", scheduledFor: Date(timeIntervalSince1970: 2_000_000_000)),
            sourceID: second.sourceID(for: secondMailbox)
        )

        await firstSession.removeAccount(first.account)

        #expect(try FileManager.default.contentsOfDirectory(atPath: firstDirectory.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: secondDirectory.path).count == 2)
        #expect(second.pendingScheduledSends().map(\.draftID) == ["session-b"])

        await secondSession.removeAccount(second.account)
        #expect(try FileManager.default.contentsOfDirectory(atPath: secondDirectory.path).isEmpty)
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
