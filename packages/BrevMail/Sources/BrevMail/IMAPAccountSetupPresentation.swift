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
import Foundation

enum IMAPAccountSetupPresentation {
    /// How the user reached the current server/auth chrome.
    enum SetupPath: Equatable, Sendable {
        /// Waiting for Find settings or a skip shortcut.
        case undiscovered
        /// Result of explicit Find settings.
        case discovered
        /// Skip shortcut: Google OAuth (or app-password secondary).
        case google
        /// Skip shortcut: Microsoft OAuth.
        case outlook
        /// Skip shortcut or failed discovery: editable IMAP/SMTP.
        case manual
    }

    /// Skip-discovery shortcuts under the email field.
    enum SkipShortcut: String, CaseIterable, Identifiable, Sendable {
        case google
        case outlook
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .google: return String(localized: "Google", bundle: .module)
            case .outlook: return String(localized: "Outlook", bundle: .module)
            case .manual: return String(localized: "Manual IMAP/SMTP", bundle: .module)
            }
        }
    }

    /// Seeds IMAP/SMTP from a skip shortcut. Uses the typed email when it already
    /// matches the provider; otherwise applies the built-in Google/Outlook profile
    /// hosts while keeping the user's address for sign-in.
    static func skipDiscovery(
        for shortcut: SkipShortcut,
        emailAddress: String
    ) -> MailAccountDiscoveryResult? {
        switch shortcut {
        case .google:
            if let profile = MailAccountAutodiscovery.profile(forEmailAddress: emailAddress),
               providerKind(forDomain: profile.domain) == .google {
                return profile
            }
            return MailAccountAutodiscovery.googleProfile(forEmailAddress: emailAddress)
        case .outlook:
            if let profile = MailAccountAutodiscovery.profile(forEmailAddress: emailAddress),
               providerKind(forDomain: profile.domain) == .microsoft {
                return profile
            }
            return MailAccountAutodiscovery.profile(forEmailAddress: "user@outlook.com")
        case .manual:
            return MailAccountAutodiscovery.manualFallback(forEmailAddress: emailAddress)
        }
    }

    /// Whether password Add account is the primary path (vs Sign in with OAuth).
    static func showsPasswordField(
        path: SetupPath,
        incomingAuthentication: MailServerAuthentication
    ) -> Bool {
        switch path {
        case .undiscovered:
            return false
        case .discovered, .manual, .google, .outlook:
            switch incomingAuthentication {
            case .password, .appPassword:
                return true
            case .xoauth2, .encryptedPassword, .none:
                return false
            }
        }
    }

    /// Whether the Google "Use app password" secondary control should show.
    static func showsGoogleAppPasswordSecondary(
        path: SetupPath,
        discovery: MailAccountDiscoveryResult?,
        incomingAuthentication: MailServerAuthentication
    ) -> Bool {
        guard incomingAuthentication == .xoauth2 else { return false }
        if path == .google { return true }
        guard let discovery else { return false }
        return providerKind(forDomain: discovery.domain) == .google
            && [discovery.incoming?.authentication, discovery.outgoing?.authentication]
            .compactMap { $0 }
            .contains(.xoauth2)
    }

    /// Whether Sign in with Google/Microsoft should be the primary CTA.
    static func showsOAuthPrimary(
        path: SetupPath,
        discovery: MailAccountDiscoveryResult?,
        incomingAuthentication: MailServerAuthentication
    ) -> Bool {
        guard incomingAuthentication == .xoauth2 else { return false }
        switch path {
        case .google, .outlook:
            return true
        case .discovered:
            guard let discovery else { return false }
            return [discovery.incoming?.authentication, discovery.outgoing?.authentication]
                .compactMap { $0 }
                .contains(.xoauth2)
        case .manual, .undiscovered:
            return false
        }
    }

    static let privacyDisclosure = String(
        localized: "Find settings uses DNS records for your domain first. If needed, provider HTTPS autoconfig may receive your full email address to return IMAP/SMTP settings.",
        bundle: .module
    )
    static let connectionTestSuccessMessage = String(
        localized: "IMAP and SMTP connection test succeeded. No account was saved.",
        bundle: .module
    )
    static let connectionTestUnavailableMessage = String(
        localized: "Connection testing is not available in this build.",
        bundle: .module
    )
    static let advancedSetupCaption = String(
        localized: "Choose a provider shortcut or enter server details yourself.",
        bundle: .module
    )
    static let emailFirstSubtitle = String(
        localized: "Enter your email and Brev will find the right connection settings.",
        bundle: .module
    )
    static let keychainPrivacyNote = String(
        localized: "Credentials are stored in Keychain. Brev connects directly to your mail provider.",
        bundle: .module
    )

    struct OAuthAction: Equatable, Sendable {
        let provider: IMAPOAuthProvider
        let title: String
        let isEnabled: Bool
        let helpText: String
    }

    struct NativeExchangeGuidance: Equatable, Sendable {
        let title: String
        let message: String
    }

    static func showsAccountDetails(
        path: SetupPath,
        isReauthentication: Bool
    ) -> Bool {
        isReauthentication || path != .undiscovered
    }

    static func showsAdvancedServerFields(
        isAdvancedSetupExpanded: Bool,
        visibility: ServerFieldVisibility
    ) -> Bool {
        isAdvancedSetupExpanded && visibility != .hidden
    }

    enum ServerFieldVisibility: Equatable, Sendable {
        case hidden
        case summaryOnly
        case editable
    }

    struct State: Equatable, Sendable {
        let emailAddress: String
        let password: String
        let incomingHost: String
        let incomingPort: String
        let incomingTLSMode: MailServerTLSMode
        let incomingAuthentication: MailServerAuthentication
        let incomingUsernameTemplate: String
        let outgoingHost: String
        let outgoingPort: String
        let outgoingTLSMode: MailServerTLSMode
        let outgoingAuthentication: MailServerAuthentication
        let outgoingUsernameTemplate: String

        init(
            emailAddress: String,
            password: String,
            incomingHost: String,
            incomingPort: String,
            incomingTLSMode: MailServerTLSMode,
            incomingAuthentication: MailServerAuthentication = .password,
            incomingUsernameTemplate: String = "%EMAILADDRESS%",
            outgoingHost: String,
            outgoingPort: String,
            outgoingTLSMode: MailServerTLSMode = .startTLS,
            outgoingAuthentication: MailServerAuthentication = .password,
            outgoingUsernameTemplate: String = "%EMAILADDRESS%"
        ) {
            self.emailAddress = emailAddress
            self.password = password
            self.incomingHost = incomingHost
            self.incomingPort = incomingPort
            self.incomingTLSMode = incomingTLSMode
            self.incomingAuthentication = incomingAuthentication
            self.incomingUsernameTemplate = incomingUsernameTemplate
            self.outgoingHost = outgoingHost
            self.outgoingPort = outgoingPort
            self.outgoingTLSMode = outgoingTLSMode
            self.outgoingAuthentication = outgoingAuthentication
            self.outgoingUsernameTemplate = outgoingUsernameTemplate
        }
    }

    static func canSubmit(_ state: State) -> Bool {
        isValidEmailAddress(state.emailAddress)
            && !trimmed(state.password).isEmpty
            && isValidHost(state.incomingHost)
            && isValidPort(state.incomingPort)
            && isValidHost(state.outgoingHost)
            && isValidPort(state.outgoingPort)
            && credentialWarning(state) == nil
            && usernameTemplateWarning(state) == nil
            && authenticationWarning(state) == nil
    }

    static func canDiscoverSettings(
        emailAddress: String,
        isDiscoveryAvailable: Bool
    ) -> Bool {
        isDiscoveryAvailable && isValidEmailAddress(emailAddress)
    }

    static func discoveryValidationMessage(
        emailAddress: String,
        isDiscoveryAvailable: Bool
    ) -> String? {
        guard isDiscoveryAvailable else {
            return String(
                localized: "Automatic settings discovery is not available in this build. Enter IMAP and SMTP settings manually.",
                bundle: .module
            )
        }
        guard isValidEmailAddress(emailAddress) else {
            return String(localized: "Enter a valid email address before using Find settings.", bundle: .module)
        }
        return nil
    }

    static func serverFieldVisibility(
        discovery: MailAccountDiscoveryResult?,
        showServerFields: Bool,
        path: SetupPath
    ) -> ServerFieldVisibility {
        if path == .manual || showServerFields {
            return .editable
        }

        guard let discovery else {
            return .hidden
        }

        // Confident matches stay behind "Show server settings". Manual fallback
        // (guessed hosts) and the Manual skip path show fields up front.
        return discovery.requiresManualReview ? .editable : .summaryOnly
    }

    static func authenticationWarning(_ state: State) -> String? {
        let candidates: [(label: String, authentication: MailServerAuthentication)] = [
            (String(localized: "Incoming IMAP", bundle: .module), state.incomingAuthentication),
            (String(localized: "Outgoing SMTP", bundle: .module), state.outgoingAuthentication),
        ]
        guard let unsupported = candidates.first(where: { !isSupportedAuthentication($0.authentication) }) else {
            return nil
        }

        switch unsupported.authentication {
        case .xoauth2:
            return oauthWarning(
                provider: providerKind(forEmailAddress: state.emailAddress),
                componentLabel: unsupported.label
            )
        case .encryptedPassword:
            return String(
                localized: "\(unsupported.label) uses encrypted-password challenge authentication, which Brev does not support yet. Change it to Password or App Password over TLS/STARTTLS before adding the account.",
                bundle: .module
            )
        case .none:
            return String(localized: "Accounts without authentication are not supported.", bundle: .module)
        case .password, .appPassword:
            return nil
        }
    }

    static func credentialWarning(_ state: State) -> String? {
        if state.password.unicodeScalars.contains(where: { $0.value == 0 }) {
            return String(localized: "Password or app password contains an invalid character.", bundle: .module)
        }
        return nil
    }

    static func usernameTemplateWarning(_ state: State) -> String? {
        let templates = [
            state.incomingUsernameTemplate,
            state.outgoingUsernameTemplate,
        ]
        guard templates.contains(where: hasUnsafeUsernameTemplateCharacters) else {
            return nil
        }
        return String(localized: "username templates cannot contain line breaks or invalid characters.", bundle: .module)
    }

    static func setupRequest(
        emailAddress: String,
        displayName: String,
        password: String,
        discovery: MailAccountDiscoveryResult
    ) -> IMAPAccountSetupRequest {
        let normalizedDisplayName = trimmed(displayName)
        return IMAPAccountSetupRequest(
            emailAddress: trimmed(emailAddress),
            displayName: normalizedDisplayName.isEmpty ? nil : normalizedDisplayName,
            password: password,
            discovery: discovery
        )
    }

    static func editedDiscovery(
        state: State,
        baseDiscovery: MailAccountDiscoveryResult?
    ) -> MailAccountDiscoveryResult? {
        guard let incomingPort = UInt16(trimmed(state.incomingPort)),
              let outgoingPort = UInt16(trimmed(state.outgoingPort)),
              !trimmed(state.incomingHost).isEmpty,
              !trimmed(state.outgoingHost).isEmpty
        else {
            return nil
        }

        return MailAccountDiscoveryResult(
            domain: emailAddressDomain(state.emailAddress),
            displayName: baseDiscovery?.displayName,
            source: baseDiscovery?.source ?? .manualFallback,
            sourceURL: baseDiscovery?.sourceURL,
            incoming: MailServerSettings(
                kind: .imap,
                host: trimmed(state.incomingHost),
                port: incomingPort,
                tlsMode: state.incomingTLSMode,
                authentication: state.incomingAuthentication,
                usernameTemplate: usernameTemplate(state.incomingUsernameTemplate)
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: trimmed(state.outgoingHost),
                port: outgoingPort,
                tlsMode: state.outgoingTLSMode,
                authentication: state.outgoingAuthentication,
                usernameTemplate: usernameTemplate(state.outgoingUsernameTemplate)
            ),
            requiresManualReview: true
        )
    }

    static func discoveryGuidance(for discovery: MailAccountDiscoveryResult) -> String? {
        let authentications = [
            discovery.incoming?.authentication,
            discovery.outgoing?.authentication,
        ]
        .compactMap { $0 }

        if authentications.contains(.xoauth2) {
            return oauthDiscoveryGuidance(for: discovery)
        }

        if authentications.contains(.encryptedPassword) {
            return String(
                localized: "Brev found encrypted-password challenge settings, which are not supported yet. Edit the account to use Password or App Password over TLS/STARTTLS before adding it.",
                bundle: .module
            )
        }

        if authentications.contains(.appPassword) {
            return appPasswordGuidance(providerName: discovery.displayName)
        }

        if discovery.requiresManualReview {
            return String(localized: "Review the discovered IMAP and SMTP settings before adding the account.", bundle: .module)
        }

        return nil
    }

    static func nativeExchangeGuidance(
        for discovery: MailAccountDiscoveryResult
    ) -> NativeExchangeGuidance? {
        guard isMicrosoftExchangeDiscovery(discovery) else { return nil }
        return NativeExchangeGuidance(
            title: String(localized: "Native Exchange support is planned", bundle: .module),
            message: String(
                localized: "Brev's current Microsoft sign-in uses IMAP and SMTP. Where IMAP is disabled for a Microsoft 365 tenant, this mailbox will need future native Exchange support through Microsoft Graph, with EWS compatibility evaluated for on-prem or hybrid accounts.",
                bundle: .module
            )
        )
    }

    static func oauthAction(
        for discovery: MailAccountDiscoveryResult,
        isOAuthSetupAvailable: Bool,
        configuration: OAuthClientConfiguration
    ) -> OAuthAction? {
        let authentications = [
            discovery.incoming?.authentication,
            discovery.outgoing?.authentication,
        ]
        .compactMap { $0 }

        guard authentications.contains(.xoauth2) else { return nil }

        switch providerKind(forDomain: discovery.domain) {
        case .google:
            return oauthAction(
                for: .google,
                isOAuthSetupAvailable: isOAuthSetupAvailable,
                configuration: configuration
            )
        case .microsoft:
            return oauthAction(
                for: .microsoft,
                isOAuthSetupAvailable: isOAuthSetupAvailable,
                configuration: configuration
            )
        case .generic:
            return nil
        }
    }

    static func oauthAction(
        for provider: IMAPOAuthProvider,
        isOAuthSetupAvailable: Bool,
        configuration: OAuthClientConfiguration
    ) -> OAuthAction {
        switch provider {
        case .google:
            guard isOAuthSetupAvailable else {
                return OAuthAction(
                    provider: .google,
                    title: String(localized: "Google sign-in not available", bundle: .module),
                    isEnabled: false,
                    helpText: String(localized: "OAuth sign-in is not available in this build.", bundle: .module)
                )
            }
            let isEnabled = configuration.canStartGoogleOAuth
            return OAuthAction(
                provider: .google,
                title: isEnabled
                    ? String(localized: "Sign in with Google", bundle: .module)
                    : String(localized: "Google sign-in not configured", bundle: .module),
                isEnabled: isEnabled,
                helpText: isEnabled
                    ? String(
                        localized: "Brev will open Google sign-in and request IMAP/SMTP access for this mailbox.",
                        bundle: .module
                    )
                    : String(
                        localized: "A platform-specific Google OAuth client ID is needed before Brev can open Google sign-in. Configure a Desktop client for macOS or an iOS client with its reversed callback in Google Cloud Console, then rebuild Brev.",
                        bundle: .module
                    )
            )
        case .microsoft:
            guard isOAuthSetupAvailable else {
                return OAuthAction(
                    provider: .microsoft,
                    title: String(localized: "Microsoft sign-in not available", bundle: .module),
                    isEnabled: false,
                    helpText: String(localized: "OAuth sign-in is not available in this build.", bundle: .module)
                )
            }
            let isEnabled = configuration.canStartMicrosoftOAuth
            return OAuthAction(
                provider: .microsoft,
                title: isEnabled
                    ? String(localized: "Sign in with Microsoft", bundle: .module)
                    : String(localized: "Microsoft sign-in not configured", bundle: .module),
                isEnabled: isEnabled,
                helpText: isEnabled
                    ? String(
                        localized: "Brev will open Microsoft sign-in and request IMAP/SMTP access for this mailbox. Tenants that disable IMAP will need future native Exchange support.",
                        bundle: .module
                    )
                    : String(
                        localized: "A Microsoft OAuth client ID is needed before Brev can open Microsoft IMAP/SMTP sign-in. If your Microsoft 365 tenant has IMAP disabled, wait for future native Exchange support.",
                        bundle: .module
                    )
            )
        }
    }

    /// Provider-specific guidance pointing the user at where to create an
    /// app-specific password.
    static func appPasswordGuidance(providerName: String?) -> String {
        switch providerName {
        case "iCloud Mail":
            return String(
                localized: "iCloud Mail requires an app-specific password — not your Apple ID password. Create one at appleid.apple.com → Sign-In and Security → App-Specific Passwords.",
                bundle: .module
            )
        case "Fastmail":
            return String(
                localized: "Fastmail requires an app password — not your login password. Create one in Fastmail → Settings → Privacy & Security → Connected apps & app passwords.",
                bundle: .module
            )
        case "Yahoo Mail":
            return String(
                localized: "Yahoo requires an app password — not your login password. Generate one in Yahoo → Account Security → Generate app password.",
                bundle: .module
            )
        case "AOL Mail":
            return String(
                localized: "AOL requires an app password — not your login password. Generate one in AOL → Account Security → Generate app password.",
                bundle: .module
            )
        default:
            return String(
                localized: "This provider expects a provider-generated app password. Enter that app password here, not your normal mailbox password.",
                bundle: .module
            )
        }
    }

    static func appPasswordHelpURL(providerName: String?) -> URL? {
        switch providerName {
        case "iCloud Mail":
            return URL(string: "https://appleid.apple.com/account/manage")
        default:
            return nil
        }
    }

    static func appPasswordHelpActionTitle(providerName: String?) -> String? {
        guard appPasswordHelpURL(providerName: providerName) != nil else { return nil }
        switch providerName {
        case "iCloud Mail":
            return String(localized: "Create app-specific password", bundle: .module)
        default:
            return nil
        }
    }

    static func setupFailureMessage(forSessionSignInError message: String) -> String {
        if message == MailBackendError.authenticationRequired.localizedDescription {
            return String(
                localized: "The server rejected these credentials. Check the email address and app password, then try again.",
                bundle: .module
            )
        }
        return message
    }

    static func connectionTestFailureMessage(for error: any Error) -> String {
        if case MailBackendError.authenticationRequired = error {
            return setupFailureMessage(
                forSessionSignInError: MailBackendError.authenticationRequired.localizedDescription
            )
        }
        if case IMAPClientError.connectionLimitExceeded = error {
            return String(
                localized: "The mail server has too many open connections right now. Wait a moment and try again.",
                bundle: .module
            )
        }
        if case IMAPClientError.authenticationFailed = error {
            return String(
                localized: "IMAP authentication failed. Check the email address and app password, then try again.",
                bundle: .module
            )
        }
        if case SMTPClientError.authenticationFailed = error {
            return String(
                localized: "SMTP authentication failed. Check the email address and app password, then try again.",
                bundle: .module
            )
        }
        return AppSessionPresentation.signInErrorMessage(for: error)
    }

    static func reauthenticationGuidance(emailAddress: String?) -> String? {
        guard let emailAddress,
              let discovery = MailAccountAutodiscovery.profile(forEmailAddress: emailAddress),
              discovery.incoming?.authentication == .appPassword
        else {
            return nil
        }
        return appPasswordGuidance(providerName: discovery.displayName)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func emailAddressDomain(_ value: String) -> String {
        let parts = trimmed(value).split(separator: "@", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]).lowercased() : ""
    }

    private static func usernameTemplate(_ value: String) -> String {
        let trimmedValue = trimmed(value)
        return trimmedValue.isEmpty ? "%EMAILADDRESS%" : trimmedValue
    }

    private static func isValidEmailAddress(_ value: String) -> Bool {
        MailAccountAutodiscovery.isValidEmailAddress(value)
    }

    private static func isValidHost(_ value: String) -> Bool {
        MailAccountAutodiscovery.isValidServerHost(value)
    }

    private static func isValidPort(_ value: String) -> Bool {
        guard let port = UInt16(trimmed(value)) else { return false }
        return port > 0
    }

    private static func isSupportedAuthentication(
        _ authentication: MailServerAuthentication
    ) -> Bool {
        switch authentication {
        case .password, .appPassword:
            return true
        case .encryptedPassword, .xoauth2, .none:
            return false
        }
    }

    private static func hasUnsafeUsernameTemplateCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value == 0
                || CharacterSet.newlines.contains(scalar)
        }
    }

    private static func oauthWarning(
        provider: OAuthGuidanceProvider,
        componentLabel: String
    ) -> String {
        switch provider {
        case .microsoft:
            return String(
                localized: "\(componentLabel) uses Microsoft OAuth2. Prefer Sign in with Microsoft when this build has a Microsoft OAuth client ID. Manual password IMAP/SMTP setup is usually blocked for Outlook and Microsoft 365 mailboxes.",
                bundle: .module
            )
        case .google:
            return String(
                localized: "\(componentLabel) uses Google OAuth2. Prefer Sign in with Google when this build has a Google OAuth client ID, or use a Google app password from a 2-Step Verification-enabled account.",
                bundle: .module
            )
        case .generic:
            return String(
                localized: "\(componentLabel) uses OAuth2. Prefer Sign in with Google or Microsoft when configured for this build, or use an IMAP/SMTP app password if your provider supports one.",
                bundle: .module
            )
        }
    }

    private static func oauthDiscoveryGuidance(for discovery: MailAccountDiscoveryResult) -> String {
        switch providerKind(forDomain: discovery.domain) {
        case .microsoft:
            return String(
                localized: "Brev found Microsoft OAuth2 settings for \(discovery.displayName ?? discovery.domain). Prefer Sign in with Microsoft when configured; manual password IMAP/SMTP setup is usually blocked for Outlook and Microsoft 365 accounts.",
                bundle: .module
            )
        case .google:
            return String(
                localized: "Brev found Google OAuth2 settings for \(discovery.displayName ?? discovery.domain). Prefer Sign in with Google when configured, or use manual IMAP/SMTP settings with a Google app password if the mailbox has 2-Step Verification enabled.",
                bundle: .module
            )
        case .generic:
            return String(
                localized: "Brev found OAuth2 settings for \(discovery.displayName ?? discovery.domain). Prefer Sign in with Google or Microsoft when configured, or use manual IMAP/SMTP settings with an app password if your provider supports one.",
                bundle: .module
            )
        }
    }

    private static func providerKind(forEmailAddress emailAddress: String) -> OAuthGuidanceProvider {
        providerKind(forDomain: emailAddressDomain(emailAddress))
    }

    private static func providerKind(forDomain domain: String) -> OAuthGuidanceProvider {
        let normalized = domain.lowercased()
        if ["gmail.com", "googlemail.com"].contains(normalized) || normalized.hasSuffix(".google.com") {
            return .google
        }
        if ["outlook.com", "hotmail.com", "live.com", "msn.com", "office365.com"].contains(normalized)
            || normalized.hasSuffix(".outlook.com")
            || normalized.hasSuffix(".microsoft.com") {
            return .microsoft
        }
        return .generic
    }

    private static func isMicrosoftExchangeDiscovery(
        _ discovery: MailAccountDiscoveryResult
    ) -> Bool {
        if providerKind(forDomain: discovery.domain) == .microsoft {
            return true
        }

        let displayName = discovery.displayName?.lowercased() ?? ""
        if ["microsoft", "outlook", "office 365", "exchange"].contains(where: displayName.contains) {
            return true
        }

        let hosts = [
            discovery.incoming?.host,
            discovery.outgoing?.host,
        ]
        .compactMap { $0?.lowercased() }

        return hosts.contains { host in
            host.contains("outlook.office365.com")
                || host.contains("smtp.office365.com")
                || host.contains("exchange")
        }
    }
}

private enum OAuthGuidanceProvider {
    case google
    case microsoft
    case generic
}
