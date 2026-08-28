/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software (the "Software"), including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, subject to the conditions in the LICENSE file.
 */

#if os(macOS)
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Login view snapshots")
@MainActor
struct LoginViewSnapshotTests {
    @Test("brand mark uses the shipped Brev app icon artwork")
    func brandIconArtwork() {
        let view = BrevBrandIcon(size: 64, cornerRadius: BrevRadius.lg)
            .frame(width: 96, height: 96)
            .brevTheme(BrevTheme.brevMonoLight)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 96, height: 96)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 96, height: 96)),
            named: "app-icon-artwork",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("compact onboarding keeps both provider paths and the privacy note visible")
    func compactOnboarding() {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: SnapshotTokenStore(),
            imapAccountSetupCoordinator: { _ in
                fatalError("not called by the snapshot")
            },
            googleOAuthLoginCoordinator: {
                fatalError("not called by the snapshot")
            }
        )
        let view = LoginView(session: session)
            .frame(width: 393, height: 852)
            .brevTheme(BrevTheme.brevMonoLight)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 393, height: 852)),
            named: "compact-google-and-imap",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("compact Google IMAP fallback uses route-neutral connection copy")
    func compactGoogleIMAPFallback() {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: SnapshotTokenStore(),
            imapOAuthBrowserCoordinator: { _ in
                fatalError("not called by the snapshot")
            }
        )
        let view = LoginView(session: session)
            .frame(width: 393, height: 700)
            .brevTheme(BrevTheme.brevMonoLight)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 393, height: 700)),
            named: "compact-google-imap-fallback",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("wide light onboarding keeps a restrained two-column hierarchy")
    func wideLightOnboarding() {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: SnapshotTokenStore(),
            imapAccountSetupCoordinator: { _ in
                fatalError("not called by the snapshot")
            },
            googleOAuthLoginCoordinator: {
                fatalError("not called by the snapshot")
            }
        )
        let view = LoginView(session: session)
            .frame(width: 956, height: 638)
            .brevTheme(BrevTheme.brevMonoLight)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 956, height: 638)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 956, height: 638)),
            named: "wide-light",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("wide onboarding keeps the account path and privacy note visible")
    func wideOnboarding() {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: SnapshotTokenStore(),
            imapAccountSetupCoordinator: { _ in
                fatalError("not called by the snapshot")
            },
            googleOAuthLoginCoordinator: {
                fatalError("not called by the snapshot")
            }
        )
        let view = LoginView(session: session)
            .frame(width: 956, height: 638)
            .brevTheme(BrevTheme.brevMonoDark)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 956, height: 638)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 956, height: 638)),
            named: "wide-google-path",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("wide onboarding keeps a visible escape hatch during Google sign-in")
    func wideOnboardingSigningIn() {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: SnapshotTokenStore(),
            googleOAuthLoginCoordinator: {
                fatalError("not called by the snapshot")
            }
        )
        session.isSigningIn = true
        let view = LoginView(session: session)
            .frame(width: 956, height: 638)
            .brevTheme(BrevTheme.brevMonoDark)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 956, height: 638)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 956, height: 638)),
            named: "wide-google-signing-in",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("compact onboarding keeps restore recovery to one inline action")
    func compactOnboardingRecovery() {
        let session = AppSession(
            initialSignInError: "Saved account settings are incomplete. Add the account again or update it in Settings.",
            accountStore: InMemoryAccountStore(),
            tokenStore: SnapshotTokenStore(),
            imapAccountSetupCoordinator: { _ in
                fatalError("not called by the snapshot")
            }
        )
        session.canRetrySessionRestore = true
        let view = LoginView(session: session)
            .frame(width: 460, height: 638)
            .brevTheme(BrevTheme.brevMonoDark)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 460, height: 638)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 460, height: 638)),
            named: "compact-recovery-retry",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("manual account setup starts with email discovery and collapsed advanced controls")
    func manualAccountSetupStartsEmailFirst() {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: SnapshotTokenStore(),
            imapAccountSetupCoordinator: { _ in
                fatalError("not called by the snapshot")
            },
            imapAccountDiscoveryCoordinator: { _ in
                fatalError("not called by the snapshot")
            }
        )
        let view = IMAPAccountSetupSheet(session: session, onClose: {})
            .frame(width: 560, height: 680)
            .brevTheme(BrevTheme.brevMonoLight)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 560, height: 680)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 680)),
            named: "imap-email-first",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}

private actor SnapshotTokenStore: TokenStore {
    func token(for accountID: String) async -> Token? { nil }
    func setToken(_ token: Token, for accountID: String) async throws {}
    func clearToken(for accountID: String) async {}
}
#endif
