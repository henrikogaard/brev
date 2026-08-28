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
import Testing

@Suite("IMAPAccountSetupPresentation")
struct IMAPAccountSetupPresentationTests {
    @Test("privacy disclosure explains DNS and full email autoconfig probes")
    func privacyDisclosureExplainsAutodiscoveryNetworkScope() {
        let disclosure = IMAPAccountSetupPresentation.privacyDisclosure

        #expect(disclosure.localizedCaseInsensitiveContains("DNS"))
        #expect(disclosure.localizedCaseInsensitiveContains("domain"))
        #expect(disclosure.localizedCaseInsensitiveContains("full email address"))
    }

    @Test("first setup step stays email-first and avoids server jargon")
    func firstSetupStepStaysEmailFirst() {
        let subtitle = IMAPAccountSetupPresentation.emailFirstSubtitle

        #expect(subtitle.localizedCaseInsensitiveContains("email"))
        #expect(subtitle.localizedCaseInsensitiveContains("find"))
        #expect(!subtitle.localizedCaseInsensitiveContains("IMAP"))
        #expect(!subtitle.localizedCaseInsensitiveContains("SMTP"))
        #expect(!subtitle.localizedCaseInsensitiveContains("skip"))
    }

    @Test("account details appear only after discovery or during password repair")
    func accountDetailsFollowDiscovery() {
        #expect(!IMAPAccountSetupPresentation.showsAccountDetails(
            path: .undiscovered,
            isReauthentication: false
        ))
        #expect(IMAPAccountSetupPresentation.showsAccountDetails(
            path: .discovered,
            isReauthentication: false
        ))
        #expect(IMAPAccountSetupPresentation.showsAccountDetails(
            path: .undiscovered,
            isReauthentication: true
        ))
    }

    @Test("manual server details remain gated by Advanced setup")
    func manualServerDetailsRemainAdvanced() {
        #expect(!IMAPAccountSetupPresentation.showsAdvancedServerFields(
            isAdvancedSetupExpanded: false,
            visibility: .editable
        ))
        #expect(IMAPAccountSetupPresentation.showsAdvancedServerFields(
            isAdvancedSetupExpanded: true,
            visibility: .editable
        ))
        #expect(!IMAPAccountSetupPresentation.showsAdvancedServerFields(
            isAdvancedSetupExpanded: true,
            visibility: .hidden
        ))
    }

    @Test("discovery is available only for valid email addresses")
    func discoveryIsAvailableOnlyForValidEmailAddresses() {
        #expect(IMAPAccountSetupPresentation.canDiscoverSettings(
            emailAddress: " person@example.org ",
            isDiscoveryAvailable: true
        ))
        #expect(!IMAPAccountSetupPresentation.canDiscoverSettings(
            emailAddress: "not-an-email",
            isDiscoveryAvailable: true
        ))
        #expect(!IMAPAccountSetupPresentation.canDiscoverSettings(
            emailAddress: "person@example_org.com",
            isDiscoveryAvailable: true
        ))
        #expect(!IMAPAccountSetupPresentation.canDiscoverSettings(
            emailAddress: " ",
            isDiscoveryAvailable: true
        ))
        #expect(!IMAPAccountSetupPresentation.canDiscoverSettings(
            emailAddress: "person@example.org",
            isDiscoveryAvailable: false
        ))
    }

    @Test("invalid discovery email explains local validation before network probes")
    func invalidDiscoveryEmailExplainsLocalValidation() throws {
        let message = try #require(
            IMAPAccountSetupPresentation.discoveryValidationMessage(
                emailAddress: "not-an-email",
                isDiscoveryAvailable: true
            )
        )

        #expect(message.localizedCaseInsensitiveContains("valid email"))
        #expect(message.localizedCaseInsensitiveContains("Find settings"))
    }

    @Test("connection test status copy explains non-persisting validation")
    func connectionTestStatusCopyExplainsNonPersistingValidation() {
        #expect(IMAPAccountSetupPresentation.connectionTestSuccessMessage.localizedCaseInsensitiveContains("IMAP"))
        #expect(IMAPAccountSetupPresentation.connectionTestSuccessMessage.localizedCaseInsensitiveContains("SMTP"))
        #expect(IMAPAccountSetupPresentation.connectionTestSuccessMessage.localizedCaseInsensitiveContains("No account"))
        #expect(IMAPAccountSetupPresentation.connectionTestUnavailableMessage.localizedCaseInsensitiveContains("not available"))
    }

    @Test("server fields stay hidden until setup has discovered or manual settings")
    func serverFieldsStayHiddenUntilSetupHasSettings() {
        #expect(IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: nil,
            showServerFields: false,
            path: .undiscovered
        ) == .hidden)
        #expect(IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: nil,
            showServerFields: true,
            path: .undiscovered
        ) == .editable)
        #expect(IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: nil,
            showServerFields: false,
            path: .manual
        ) == .editable)
    }

    @Test("built-in provider settings summarize before exposing server fields")
    func builtInProviderSettingsSummarizeBeforeExposingServerFields() throws {
        let discovery = try #require(MailAccountAutodiscovery.profile(forEmailAddress: "person@fastmail.com"))

        #expect(IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: discovery,
            showServerFields: false,
            path: .discovered
        ) == .summaryOnly)
        #expect(IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: discovery,
            showServerFields: true,
            path: .discovered
        ) == .editable)
    }

    @Test("skip shortcuts seed Google Outlook and manual IMAP/SMTP")
    func skipShortcutsSeedProviderServers() throws {
        let google = try #require(
            IMAPAccountSetupPresentation.skipDiscovery(for: .google, emailAddress: "person@gmail.com")
        )
        #expect(google.source == .builtInProfile)
        #expect(google.incoming?.host == "imap.gmail.com")
        #expect(google.incoming?.authentication == .xoauth2)

        let outlook = try #require(
            IMAPAccountSetupPresentation.skipDiscovery(for: .outlook, emailAddress: "person@outlook.com")
        )
        #expect(outlook.source == .builtInProfile)
        #expect(outlook.incoming?.authentication == .xoauth2)

        let manual = try #require(
            IMAPAccountSetupPresentation.skipDiscovery(for: .manual, emailAddress: "person@example.org")
        )
        #expect(manual.source == .manualFallback)
        #expect(manual.requiresManualReview)
    }

    @Test("Google path shows OAuth primary and app-password secondary")
    func googlePathShowsOAuthPrimaryAndAppPasswordSecondary() throws {
        let discovery = try #require(
            IMAPAccountSetupPresentation.skipDiscovery(for: .google, emailAddress: "person@gmail.com")
        )
        #expect(IMAPAccountSetupPresentation.showsOAuthPrimary(
            path: .google,
            discovery: discovery,
            incomingAuthentication: .xoauth2
        ))
        #expect(IMAPAccountSetupPresentation.showsGoogleAppPasswordSecondary(
            path: .google,
            discovery: discovery,
            incomingAuthentication: .xoauth2
        ))
        #expect(!IMAPAccountSetupPresentation.showsPasswordField(
            path: .google,
            incomingAuthentication: .xoauth2
        ))
        #expect(IMAPAccountSetupPresentation.showsPasswordField(
            path: .google,
            incomingAuthentication: .appPassword
        ))
    }

    @Test("the manual fallback exposes server fields immediately for review")
    func manualFallbackExposesServerFields() {
        let discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )

        #expect(IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: discovery,
            showServerFields: false,
            path: .discovered
        ) == .editable)
    }

    @Test("a confident DNS match summarizes server fields like a built-in profile")
    func confidentDiscoverySummarizesServerFields() throws {
        // fastmail → messagingengine MX is a confident match (no manual review).
        let discovery = try #require(
            MailAccountAutodiscovery.providerResult(
                forMXRecords: [MailMXRecord(preference: 5, exchange: "in1-smtp.messagingengine.com")],
                emailAddress: "henrik@example.com"
            )
        )
        #expect(discovery.requiresManualReview == false)
        #expect(discovery.displayName == "Fastmail")
        #expect(IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: discovery,
            showServerFields: false,
            path: .discovered
        ) == .summaryOnly)
    }

    @Test("setup auth errors explain credentials instead of stale session sign-in")
    func setupAuthErrorsExplainCredentialsInsteadOfStaleSessionSignIn() {
        let message = IMAPAccountSetupPresentation.setupFailureMessage(
            forSessionSignInError: MailBackendError.authenticationRequired.localizedDescription
        )

        #expect(message.localizedCaseInsensitiveContains("credentials"))
        #expect(message.localizedCaseInsensitiveContains("app password"))
        #expect(!message.localizedCaseInsensitiveContains("sign in again"))
    }

    @Test("connection test auth errors explain the account credentials")
    func connectionTestAuthErrorsExplainAccountCredentials() {
        let message = IMAPAccountSetupPresentation.connectionTestFailureMessage(
            for: IMAPClientError.authenticationFailed("A2 NO authentication failed")
        )

        #expect(message.localizedCaseInsensitiveContains("IMAP authentication failed"))
        #expect(message.localizedCaseInsensitiveContains("app password"))
    }

    @Test("unavailable discovery explains manual setup remains available")
    func unavailableDiscoveryExplainsManualSetupRemainsAvailable() throws {
        let message = try #require(
            IMAPAccountSetupPresentation.discoveryValidationMessage(
                emailAddress: "person@example.org",
                isDiscoveryAvailable: false
            )
        )

        #expect(message.localizedCaseInsensitiveContains("automatic"))
        #expect(message.localizedCaseInsensitiveContains("manual"))
        #expect(!message.localizedCaseInsensitiveContains("valid email"))
    }

    @Test("incoming STARTTLS no longer blocks account submission")
    func incomingSTARTTLSNoLongerBlocksSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "143",
            incomingTLSMode: .startTLS,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )

        #expect(IMAPAccountSetupPresentation.canSubmit(state))
    }

    @Test("invalid server ports still block account submission")
    func invalidServerPortsStillBlockSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "not-a-port",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(state))
    }

    @Test("pasted whitespace around account settings does not block submission")
    func pastedWhitespaceAroundAccountSettingsDoesNotBlockSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: " person@example.org ",
            password: "app-password",
            incomingHost: " imap.example.org ",
            incomingPort: " 993 ",
            incomingTLSMode: .implicit,
            outgoingHost: " smtp.example.org ",
            outgoingPort: " 587 "
        )

        #expect(IMAPAccountSetupPresentation.canSubmit(state))
    }

    @Test("zero port and malformed hosts block account submission")
    func zeroPortAndMalformedHostsBlockSubmission() {
        let zeroPort = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "0",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )
        let hostWithWhitespace = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app-password",
            incomingHost: "imap example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(zeroPort))
        #expect(!IMAPAccountSetupPresentation.canSubmit(hostWithWhitespace))
    }

    @Test("host unsafe manual servers block account submission")
    func hostUnsafeManualServersBlockSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app-password",
            incomingHost: "imap_example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(state))
    }

    @Test("invalid email address blocks account submission")
    func invalidEmailAddressBlocksSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "not-an-email",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(state))
    }

    @Test("passwords containing NUL block account submission")
    func passwordsContainingNULBlockSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app\u{0}password",
            incomingHost: "imap.example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(state))
        #expect(IMAPAccountSetupPresentation.credentialWarning(state)?.contains("invalid") == true)
    }

    @Test("unsafe username templates block account submission")
    func unsafeUsernameTemplatesBlockSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            incomingUsernameTemplate: "%EMAILADDRESS%\nBAD",
            outgoingHost: "smtp.example.org",
            outgoingPort: "587",
            outgoingUsernameTemplate: "%EMAILADDRESS%"
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(state))
        #expect(IMAPAccountSetupPresentation.usernameTemplateWarning(state)?.contains("username") == true)
    }

    @Test("setup request trims address and display name while preserving password secret")
    func setupRequestTrimsAddressAndDisplayNameWhilePreservingPasswordSecret() {
        let discovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@example.org"
        )

        let request = IMAPAccountSetupPresentation.setupRequest(
            emailAddress: " Person@Example.ORG ",
            displayName: "  Person Example  ",
            password: " app-password-with-edge-space ",
            discovery: discovery
        )

        #expect(request.emailAddress == "Person@Example.ORG")
        #expect(request.displayName == "Person Example")
        #expect(request.password == " app-password-with-edge-space ")
        #expect(request.discovery == discovery)
    }

    @Test("edited discovery follows the current email address domain")
    func editedDiscoveryFollowsCurrentEmailAddressDomain() throws {
        let previousDiscovery = MailAccountAutodiscovery.manualFallback(
            forEmailAddress: "person@old.example"
        )
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: " person@new.example ",
            password: "app-password",
            incomingHost: "imap.new.example",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.new.example",
            outgoingPort: "587"
        )

        let edited = try #require(
            IMAPAccountSetupPresentation.editedDiscovery(
                state: state,
                baseDiscovery: previousDiscovery
            )
        )

        #expect(edited.domain == "new.example")
        #expect(edited.source == previousDiscovery.source)
        #expect(edited.incoming?.host == "imap.new.example")
        #expect(edited.outgoing?.host == "smtp.new.example")
    }

    @Test("host unsafe email domains block account submission")
    func hostUnsafeEmailDomainsBlockSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example_org.com",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587"
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(state))
    }

    @Test("unsupported authentication modes block account submission")
    func unsupportedAuthenticationModesBlockSubmission() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@outlook.com",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            incomingAuthentication: .xoauth2,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587",
            outgoingAuthentication: .password
        )

        #expect(!IMAPAccountSetupPresentation.canSubmit(state))
        #expect(IMAPAccountSetupPresentation.authenticationWarning(state)?.contains("OAuth2") == true)
        #expect(IMAPAccountSetupPresentation.authenticationWarning(state)?.contains("Microsoft") == true)
    }

    @Test("encrypted-password guidance explains how to edit the account settings")
    func encryptedPasswordGuidanceExplainsHowToEditTheAccountSettings() {
        let state = IMAPAccountSetupPresentation.State(
            emailAddress: "person@example.org",
            password: "app-password",
            incomingHost: "imap.example.org",
            incomingPort: "993",
            incomingTLSMode: .implicit,
            incomingAuthentication: .encryptedPassword,
            outgoingHost: "smtp.example.org",
            outgoingPort: "587",
            outgoingAuthentication: .password
        )

        let warning = IMAPAccountSetupPresentation.authenticationWarning(state)

        #expect(warning?.contains("Change") == true)
        #expect(warning?.contains("TLS/STARTTLS") == true)
    }

    @Test("discovered iCloud profile explains app-specific password and where to create one")
    func discoveredICloudProfileExplainsAppSpecificPassword() throws {
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@icloud.com")
        )

        let guidance = try #require(
            IMAPAccountSetupPresentation.discoveryGuidance(for: discovery)
        )

        #expect(guidance.localizedCaseInsensitiveContains("app-specific password"))
        #expect(guidance.localizedCaseInsensitiveContains("appleid.apple.com"))
    }

    @Test("iCloud app-password guidance exposes Apple ID action")
    func iCloudAppPasswordGuidanceExposesAppleIDAction() throws {
        let url = try #require(
            IMAPAccountSetupPresentation.appPasswordHelpURL(providerName: "iCloud Mail")
        )
        let title = try #require(
            IMAPAccountSetupPresentation.appPasswordHelpActionTitle(providerName: "iCloud Mail")
        )

        #expect(url.host == "appleid.apple.com")
        #expect(title.localizedCaseInsensitiveContains("app-specific password"))
        #expect(IMAPAccountSetupPresentation.appPasswordHelpURL(providerName: "Fastmail") == nil)
    }

    @Test("iCloud reauthentication guidance points to app-specific password")
    func iCloudReauthenticationGuidancePointsToAppSpecificPassword() throws {
        let guidance = try #require(
            IMAPAccountSetupPresentation.reauthenticationGuidance(emailAddress: "person@icloud.com")
        )

        #expect(guidance.localizedCaseInsensitiveContains("iCloud"))
        #expect(guidance.localizedCaseInsensitiveContains("app-specific password"))
        #expect(IMAPAccountSetupPresentation.reauthenticationGuidance(emailAddress: "person@example.org") == nil)
    }

    @Test("discovered OAuth profiles explain why account setup is blocked")
    func discoveredOAuthProfilesExplainWhyAccountSetupIsBlocked() throws {
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@outlook.com")
        )

        let guidance = try #require(
            IMAPAccountSetupPresentation.discoveryGuidance(for: discovery)
        )

        #expect(guidance.localizedCaseInsensitiveContains("OAuth2"))
        #expect(guidance.localizedCaseInsensitiveContains("Microsoft"))
        #expect(guidance.localizedCaseInsensitiveContains("manual password"))
    }

    @Test("Microsoft profiles expose native Exchange future-scope guidance")
    func microsoftProfilesExposeNativeExchangeFutureScopeGuidance() throws {
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@outlook.com")
        )

        let guidance = try #require(
            IMAPAccountSetupPresentation.nativeExchangeGuidance(for: discovery)
        )

        #expect(guidance.title == "Native Exchange support is planned")
        #expect(guidance.message.localizedCaseInsensitiveContains("current Microsoft sign-in uses IMAP and SMTP"))
        #expect(guidance.message.localizedCaseInsensitiveContains("Microsoft Graph"))
        #expect(guidance.message.localizedCaseInsensitiveContains("EWS"))
        #expect(guidance.message.localizedCaseInsensitiveContains("IMAP is disabled"))
    }

    @Test("non-Microsoft profiles do not expose native Exchange guidance")
    func nonMicrosoftProfilesDoNotExposeNativeExchangeGuidance() throws {
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@gmail.com")
        )

        #expect(IMAPAccountSetupPresentation.nativeExchangeGuidance(for: discovery) == nil)
    }

    @Test("explicit Google shortcut keeps custom Workspace domain while using Gmail servers")
    func googleShortcutSupportsWorkspaceCustomDomain() throws {
        let discovery = try #require(
            IMAPAccountSetupPresentation.skipDiscovery(
                for: .google,
                emailAddress: "person@example.edu"
            )
        )

        #expect(discovery.domain == "example.edu")
        #expect(discovery.displayName == "Gmail")
        #expect(discovery.incoming?.host == "imap.gmail.com")
        #expect(discovery.outgoing?.host == "smtp.gmail.com")
        #expect(discovery.incoming?.authentication == .xoauth2)
    }

    @Test("configured Google OAuth profile exposes enabled browser action")
    func configuredGoogleOAuthProfileExposesEnabledBrowserAction() throws {
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@gmail.com")
        )

        let action = try #require(
            IMAPAccountSetupPresentation.oauthAction(
                for: discovery,
                isOAuthSetupAvailable: true,
                configuration: OAuthClientConfiguration(googleClientID: "google-client")
            )
        )

        #expect(action.provider == .google)
        #expect(action.title == "Sign in with Google")
        #expect(action.isEnabled)
        #expect(action.helpText.localizedCaseInsensitiveContains("Google sign-in"))
        #expect(action.helpText.localizedCaseInsensitiveContains("IMAP/SMTP access"))
    }

    @Test("missing Microsoft OAuth client disables browser action")
    func missingMicrosoftOAuthClientDisablesBrowserAction() throws {
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@outlook.com")
        )

        let action = try #require(
            IMAPAccountSetupPresentation.oauthAction(
                for: discovery,
                isOAuthSetupAvailable: true,
                configuration: OAuthClientConfiguration()
            )
        )

        #expect(action.provider == .microsoft)
        #expect(action.title == "Microsoft sign-in not configured")
        #expect(!action.isEnabled)
        #expect(action.helpText.localizedCaseInsensitiveContains("Microsoft OAuth client ID"))
        #expect(action.helpText.localizedCaseInsensitiveContains("IMAP/SMTP"))
        #expect(action.helpText.localizedCaseInsensitiveContains("Microsoft 365 tenant has IMAP disabled"))
        #expect(action.helpText.localizedCaseInsensitiveContains("needed"))
    }

    @Test("unavailable OAuth setup explains build support separately from client configuration")
    func unavailableOAuthSetupExplainsBuildSupportSeparatelyFromClientConfiguration() throws {
        let discovery = try #require(
            MailAccountAutodiscovery.profile(forEmailAddress: "person@gmail.com")
        )

        let action = try #require(
            IMAPAccountSetupPresentation.oauthAction(
                for: discovery,
                isOAuthSetupAvailable: false,
                configuration: OAuthClientConfiguration(googleClientID: "google-client")
            )
        )

        #expect(action.provider == .google)
        #expect(action.title == "Google sign-in not available")
        #expect(!action.isEnabled)
        #expect(action.helpText == "OAuth sign-in is not available in this build.")
    }
}
