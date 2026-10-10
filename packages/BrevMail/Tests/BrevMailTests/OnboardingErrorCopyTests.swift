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
@testable import BrevMail
import Foundation
import Testing

/// Platform-correct restore/re-auth copy, the Google-unavailable login state,
/// the add-account Return policy and the sign-in banner's accessibility
/// grouping (iOS UX audit findings O1-O3).
@Suite("Onboarding error copy and policy")
struct OnboardingErrorCopyTests {
    private let sourceID = MailSourceID(accountID: "acct", mailboxID: "mbox")

    // MARK: O3 - platform-correct keychain copy

    @Test("iOS locked-keychain copy never mentions the Mac")
    func iOSKeychainLockedCopyDoesNotMentionMac() {
        let message = AppSessionPresentation.keychainLockedMessage(for: .iOS)
        #expect(!message.contains("Mac"))
        #expect(message != AppSessionPresentation.keychainLockedMessage(for: .macOS))
    }

    @Test("macOS locked-keychain copy keeps the Mac guidance")
    func macOSKeychainLockedCopyKeepsMacGuidance() {
        let message = AppSessionPresentation.keychainLockedMessage(for: .macOS)
        // Locale-independent: both English and Norwegian name the Mac.
        #expect(message.contains("Mac"))
    }

    @Test("the running platform maps to a keychain copy platform")
    func currentPlatformMatchesBuild() {
        #if os(iOS)
        #expect(AppSessionPresentation.KeychainPlatform.current == .iOS)
        #else
        #expect(AppSessionPresentation.KeychainPlatform.current == .macOS)
        #endif
    }

    // MARK: O3 - sign-in banner

    @Test("sign-in banner keeps its button separately focusable")
    func reauthenticateBannerKeepsButtonSeparate() throws {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .authenticationRequired,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 8),
            cacheSizeBytes: 2048,
            pendingMutationCount: 0
        )
        let banner = try #require(ImportProgressPresentation.resolve(health: health, folderSyncProgress: nil))

        #expect(banner.action == .reauthenticate)
        #expect(banner.accessibilityGrouping == .keepActionSeparate)
        #expect(banner.message?.isEmpty == false)
    }

    @Test("informational banners read as one element")
    func informationalBannerCombines() throws {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 12),
            cacheSizeBytes: 4096,
            pendingMutationCount: 0
        )
        let banner = try #require(
            ImportProgressPresentation.resolve(
                health: health,
                folderSyncProgress: MailSyncProgress(completed: 2, total: 5)
            )
        )

        #expect(banner.action == nil)
        #expect(banner.accessibilityGrouping == .combine)
    }

    // MARK: O2 - Google unavailable

    @Test("unconfigured Google shows a neutral notice only when no error is pending")
    func googleUnavailableNoticePolicy() {
        #expect(LoginViewPresentation.showsGoogleUnavailableNotice(googleConfigIsInvalid: true, hasSignInError: false))
        #expect(!LoginViewPresentation.showsGoogleUnavailableNotice(googleConfigIsInvalid: true, hasSignInError: true))
        #expect(!LoginViewPresentation.showsGoogleUnavailableNotice(googleConfigIsInvalid: false, hasSignInError: false))
    }

    // MARK: O1 - Return in the email field

    @Test("Return in Email runs Find settings until details are visible")
    func emailReturnRunsFindSettings() {
        #expect(IMAPAccountSetupPresentation.emailSubmitAction(showsAccountDetails: false) == .findSettings)
        #expect(IMAPAccountSetupPresentation.emailSubmitAction(showsAccountDetails: true) == .advance)
    }

    // MARK: Catalog

    @Test("onboarding strings carry Norwegian translations and the developer copy is gone")
    func stringsCarryNorwegianTranslations() throws {
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let keys = [
            "Your device is locked, so Brev can't read your saved sign-in yet. Unlock your device, then try again.",
            "Google sign-in isn't available in this build. You can still add a Gmail account with an app password.",
            "Sign-in required",
            "Reconnect this account to keep syncing mail.",
            "Sign-in required to continue syncing mail.",
            "Connecting",
            "Downloading mail",
            "Indexing mail",
            "Sync paused",
            "Sync interrupted",
            "Sync needs attention"
        ]
        for key in keys {
            let entry = strings[key] as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any]
            let unit = (localizations?["nb"] as? [String: Any])?["stringUnit"] as? [String: Any]
            #expect((unit?["value"] as? String)?.isEmpty == false, "missing nb translation: \(key)")
        }
        let developerCopy = "Google sign-in isn't configured in this build. "
            + "Provide the OAuth client ID at build time, or add a mail account instead."
        #expect(strings[developerCopy] == nil)
    }
}
