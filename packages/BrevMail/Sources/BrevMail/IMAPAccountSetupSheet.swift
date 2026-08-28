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
import BrevDesign
import BrevThemes
import SwiftUI

public struct IMAPAccountSetupSheet: View {
    @Environment(\.brevTheme) private var theme
    @Bindable private var session: AppSession

    @State private var emailAddress = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var discovery: MailAccountDiscoveryResult?
    @State private var setupPath: IMAPAccountSetupPresentation.SetupPath = .undiscovered
    @State private var incomingHost = ""
    @State private var incomingPort = "993"
    @State private var incomingTLSMode = MailServerTLSMode.implicit
    @State private var incomingAuthentication = MailServerAuthentication.password
    @State private var incomingUsernameTemplate = "%EMAILADDRESS%"
    @State private var outgoingHost = ""
    @State private var outgoingPort = "587"
    @State private var outgoingTLSMode = MailServerTLSMode.startTLS
    @State private var outgoingAuthentication = MailServerAuthentication.password
    @State private var outgoingUsernameTemplate = "%EMAILADDRESS%"
    @State private var isManageSieveEnabled = false
    @State private var manageSieveHost = ""
    @State private var manageSievePort = "4190"
    @State private var manageSieveTLSMode = MailServerTLSMode.implicit
    @State private var isDiscovering = false
    @State private var isTestingConnection = false
    @State private var localStatus: SetupStatus?
    @State private var showServerFields = false
    @State private var isAdvancedSetupExpanded = false
    @State private var hasRunReauthDiscovery = false
    @State private var didStartDiscoveryProbe = false
    @State private var oauthSignInTask: Task<Void, Never>?
    @State private var nextOAuthSignInTaskRequestID = 0
    @State private var activeOAuthSignInTaskRequest: AuthenticationTaskRequest?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, displayName, password }

    private let onClose: () -> Void
    private let oauthConfiguration: OAuthClientConfiguration
    /// When non-empty, this sheet is updating credentials for an existing account.
    private let isReauthentication: Bool

    public init(
        session: AppSession,
        initialEmailAddress: String = "",
        oauthConfiguration: OAuthClientConfiguration = .shared,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        _emailAddress = State(initialValue: initialEmailAddress)
        self.oauthConfiguration = oauthConfiguration
        self.onClose = onClose
        isReauthentication = !initialEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(spacing: BrevSpacing.lg) {
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                    header
                    accountFields
                    advancedSetupSection
                    if didStartDiscoveryProbe || setupPath != .undiscovered {
                        statusAndGuidanceSection
                    }
                }
                .frame(maxWidth: setupContentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            actions
                .frame(maxWidth: setupContentMaxWidth)
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.xl)
        #if os(iOS)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #else
            .frame(minWidth: 520, idealWidth: 560, minHeight: 560)
        #endif
            .background(theme.bgPrimary.color)
            .task {
                // Re-auth only: one-shot discover for the known failed address.
                guard isReauthentication, !hasRunReauthDiscovery else { return }
                hasRunReauthDiscovery = true
                discover(asPath: .discovered)
            }
            .onChange(of: session.signInError) { _, signInError in
                guard let signInError else { return }
                localStatus = SetupStatus(
                    message: IMAPAccountSetupPresentation.setupFailureMessage(
                        forSessionSignInError: signInError
                    ),
                    tone: .danger
                )
            }
            .onDisappear {
                cancelOAuthSignIn()
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .top, spacing: BrevSpacing.md) {
                BrevBrandIcon(size: 32, cornerRadius: BrevRadius.sm)
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(verbatim: isReauthentication
                        ? String(localized: "Update mail password", bundle: .module)
                        : String(localized: "Add mail account", bundle: .module))
                        .brevFont(.title)
                        .foregroundStyle(theme.textPrimary.color)
                    Text(verbatim: IMAPAccountSetupPresentation.emailFirstSubtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Label {
                Text(verbatim: IMAPAccountSetupPresentation.keychainPrivacyNote)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
                    .foregroundStyle(theme.textTertiary.color)
            }
        }
    }

    private var accountFields: some View {
        setupSection {
            setupField(String(localized: "Email address", bundle: .module)) {
                TextField(String("name@example.org"), text: $emailAddress)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                #endif
                    .disabled(isReauthentication)
                    .onSubmit {
                        focusedField = .displayName
                    }
            }

            findSettingsButton
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsAccountDetails {
                setupField(String(localized: "Display name (optional)", bundle: .module)) {
                    TextField(String(localized: "Name shown on the account", bundle: .module), text: $displayName)
                        .focused($focusedField, equals: .displayName)
                }

                if showsPasswordField {
                    setupField(String(localized: "Password or app password", bundle: .module)) {
                        SecureField(String(localized: "Stored locally in Keychain", bundle: .module), text: $password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.done)
                    }
                    if incomingAuthentication == .appPassword {
                        Text(verbatim: IMAPAccountSetupPresentation.appPasswordGuidance(providerName: discovery?.displayName))
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        appPasswordHelpLink
                    }
                }

                if showsOAuthPrimary, let oauthAction {
                    oauthPrimaryButton(oauthAction)
                }

                if showsGoogleAppPasswordSecondary {
                    Button(String(localized: "Use app password instead", bundle: .module)) {
                        useGoogleAppPassword()
                    }
                    .buttonStyle(.borderless)
                    .brevFont(.caption)
                    .foregroundStyle(theme.accent.color)
                    .imapSetupTouchTarget()
                }
            }
        }
    }

    private var advancedSetupSection: some View {
        DisclosureGroup(isExpanded: $isAdvancedSetupExpanded) {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                Text(verbatim: IMAPAccountSetupPresentation.advancedSetupCaption)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BrevSpacing.sm) {
                        advancedSetupShortcuts
                    }
                    VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                        advancedSetupShortcuts
                    }
                }

                if showsAdvancedServerFields {
                    serverFields
                    if serverFieldVisibility == .editable {
                        manageSieveSection
                    }
                }
            }
            .padding(.top, BrevSpacing.sm)
        } label: {
            Label(String(localized: "Advanced setup", bundle: .module), systemImage: "gearshape")
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
        }
        .tint(theme.accent.color)
        .imapSetupTouchTarget()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var advancedSetupShortcuts: some View {
        ForEach(IMAPAccountSetupPresentation.SkipShortcut.allCases) { shortcut in
            BrevButton(verbatim: shortcut.title, style: .secondary) {
                applySkip(shortcut)
            }
            .disabled(isDiscovering || session.isSigningIn)
            .imapSetupTouchTarget()
        }
    }

    private var statusAndGuidanceSection: some View {
        setupSection {
            discoverySummaryText

            Text(verbatim: IMAPAccountSetupPresentation.privacyDisclosure)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)

            nativeExchangeGuidanceSection
            statusView
        }
    }

    @ViewBuilder
    private func oauthPrimaryButton(_ action: IMAPAccountSetupPresentation.OAuthAction) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            BrevButton(verbatim: action.title, style: .primary) {
                startOAuthSignIn {
                    await session.signInWithIMAPOAuthProvider(action.provider)
                    if session.signInError == nil, session.backend != nil {
                        onClose()
                    }
                }
            }
            .disabled(!action.isEnabled || session.isSigningIn)
            .imapSetupTouchTarget()

            Text(verbatim: action.helpText)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var appPasswordHelpLink: some View {
        if let title = IMAPAccountSetupPresentation.appPasswordHelpActionTitle(
            providerName: discovery?.displayName
        ),
            let url = IMAPAccountSetupPresentation.appPasswordHelpURL(
                providerName: discovery?.displayName
            ) {
            Link(title, destination: url)
                .brevFont(.caption)
                .foregroundStyle(theme.accent.color)
        }
    }

    private var findSettingsButton: some View {
        BrevButton(
            verbatim: isDiscovering
                ? String(localized: "Finding...", bundle: .module)
                : String(localized: "Find settings", bundle: .module),
            style: .secondary
        ) {
            discover(asPath: .discovered)
        }
        .disabled(isDiscovering || !canDiscoverSettings)
        .imapSetupTouchTarget()
    }

    @ViewBuilder
    private var serverFields: some View {
        switch serverFieldVisibility {
        case .hidden:
            EmptyView()
        case .summaryOnly:
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                Button(String(localized: "Show server settings", bundle: .module)) {
                    showServerFields = true
                    isAdvancedSetupExpanded = true
                }
                .buttonStyle(.borderless)
                .brevFont(.caption)
                .foregroundStyle(theme.accent.color)
                .imapSetupTouchTarget()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .editable:
            serverSection(
                title: String(localized: "Incoming IMAP", bundle: .module),
                host: $incomingHost,
                port: $incomingPort,
                tlsMode: $incomingTLSMode,
                authentication: $incomingAuthentication,
                usernameTemplate: $incomingUsernameTemplate
            )

            serverSection(
                title: String(localized: "Outgoing SMTP", bundle: .module),
                host: $outgoingHost,
                port: $outgoingPort,
                tlsMode: $outgoingTLSMode,
                authentication: $outgoingAuthentication,
                usernameTemplate: $outgoingUsernameTemplate
            )
        }
    }

    @ViewBuilder
    private var nativeExchangeGuidanceSection: some View {
        if let nativeExchangeGuidance {
            BrevInlineStatus(
                message: [nativeExchangeGuidance.title, nativeExchangeGuidance.message]
                    .joined(separator: ". "),
                tone: .info,
                lineLimit: nil
            )
        }
    }

    private var manageSieveSection: some View {
        setupSection {
            Toggle(isOn: manageSieveEnabledBinding) {
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    Text("Server-side filters", bundle: .module)
                        .brevFont(.headline)
                        .foregroundStyle(theme.textPrimary.color)
                    Text("Sync compatible local rules to a Brev-owned ManageSieve script.", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(theme.accent.color)

            Text(
                "Brev will use this endpoint only when you choose to sync rules from Settings. It sends your account credentials and generated Sieve script to the configured mail provider.",
                bundle: .module
            )
            .brevFont(.caption)
            .foregroundStyle(theme.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)

            if isManageSieveEnabled {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BrevSpacing.md) {
                        setupField(String(localized: "Host", bundle: .module)) {
                            TextField(String("sieve.example.org"), text: $manageSieveHost)
                        }

                        setupField(String(localized: "Port", bundle: .module)) {
                            TextField(String("4190"), text: $manageSievePort)
                                .frame(width: 96)
                        }
                    }

                    VStack(alignment: .leading, spacing: BrevSpacing.md) {
                        setupField(String(localized: "Host", bundle: .module)) {
                            TextField(String("sieve.example.org"), text: $manageSieveHost)
                        }

                        setupField(String(localized: "Port", bundle: .module)) {
                            TextField(String("4190"), text: $manageSievePort)
                        }
                    }
                }

                securityPicker(selection: $manageSieveTLSMode)
            }
        }
    }

    private var discoverySummaryText: some View {
        HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xs) {
            if isDiscovering {
                ProgressView()
                    .controlSize(.small)
            } else if let discovery, !discovery.requiresManualReview {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accent.color)
                    .accessibilityHidden(true)
            }
            Text(verbatim: discoverySummary)
                .brevFont(.caption)
                .foregroundStyle(isConfidentDiscovery ? theme.textPrimary.color : theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `true` once discovery has resolved a provider that needs no manual review.
    private var isConfidentDiscovery: Bool {
        guard let discovery else { return false }
        return !discovery.requiresManualReview
    }

    @ViewBuilder
    private var statusView: some View {
        if let authenticationWarning = IMAPAccountSetupPresentation.authenticationWarning(
            setupState
        ) {
            BrevInlineStatus(
                message: authenticationWarning,
                tone: .warning,
                lineLimit: nil
            )
        } else if let credentialWarning = IMAPAccountSetupPresentation.credentialWarning(
            setupState
        ) {
            BrevInlineStatus(
                message: credentialWarning,
                tone: .warning,
                lineLimit: nil
            )
        } else if let usernameTemplateWarning = IMAPAccountSetupPresentation.usernameTemplateWarning(
            setupState
        ) {
            BrevInlineStatus(
                message: usernameTemplateWarning,
                tone: .warning,
                lineLimit: nil
            )
        } else if let discovery,
                  let guidance = IMAPAccountSetupPresentation.discoveryGuidance(
                      for: discovery
                  ) {
            BrevInlineStatus(
                message: guidance,
                tone: .info,
                lineLimit: nil
            )
        }

        if let localStatus {
            BrevInlineStatus(
                message: localStatus.message,
                tone: localStatus.tone,
                lineLimit: nil
            )
        }

        if session.canUseGoogleIMAPFallback {
            BrevInlineStatus(
                message: String(
                    localized: "Gmail API access is unavailable for this account. You can continue with Google IMAP/SMTP using XOAUTH2.",
                    bundle: .module
                ),
                tone: .info,
                actionTitle: String(localized: "Use Google IMAP/SMTP instead", bundle: .module),
                onAction: {
                    startOAuthSignIn {
                        await session.signInWithGoogleIMAPFallback()
                        if session.signInError == nil, session.backend != nil {
                            onClose()
                        }
                    }
                },
                lineLimit: nil
            )
            .imapSetupTouchTarget()
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BrevSpacing.sm) {
                cancelButton
                Spacer()
                testConnectionButton
                addAccountButton
            }

            VStack(spacing: BrevSpacing.sm) {
                addAccountButton
                    .frame(maxWidth: .infinity)
                testConnectionButton
                    .frame(maxWidth: .infinity)
                cancelButton
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var cancelButton: some View {
        BrevButton("Cancel", style: .secondary, bundle: .module) {
            cancelOAuthSignIn()
            onClose()
        }
        .imapSetupTouchTarget()
    }

    private var testConnectionButton: some View {
        BrevButton(
            verbatim: isTestingConnection
                ? String(localized: "Testing...", bundle: .module)
                : String(localized: "Test connection", bundle: .module),
            style: .secondary
        ) {
            testConnection()
        }
        .disabled(!canTestConnection)
        .imapSetupTouchTarget()
    }

    private var addAccountButton: some View {
        BrevButton(
            verbatim: session.isSigningIn
                ? String(localized: "Adding...", bundle: .module)
                : String(localized: "Add account", bundle: .module)
        ) {
            addAccount()
        }
        .disabled(!canAddAccount || session.isSigningIn || isTestingConnection)
        .imapSetupTouchTarget()
    }

    private func startOAuthSignIn(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        oauthSignInTask?.cancel()
        nextOAuthSignInTaskRequestID += 1
        let request = AuthenticationTaskRequest(id: nextOAuthSignInTaskRequestID)
        activeOAuthSignInTaskRequest = request
        oauthSignInTask = Task { @MainActor in
            await operation()
            guard AuthenticationTaskResponsePolicy.canClear(
                completedRequest: request,
                activeRequest: activeOAuthSignInTaskRequest
            ) else { return }
            activeOAuthSignInTaskRequest = nil
            oauthSignInTask = nil
        }
    }

    private func cancelOAuthSignIn() {
        activeOAuthSignInTaskRequest = nil
        oauthSignInTask?.cancel()
        oauthSignInTask = nil
        session.cancelSignIn()
    }

    private func setupSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            content()
        }
        .setupSectionSurface(theme: theme)
    }

    private func serverSection(
        title: String,
        host: Binding<String>,
        port: Binding<String>,
        tlsMode: Binding<MailServerTLSMode>,
        authentication: Binding<MailServerAuthentication>,
        usernameTemplate: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Text(verbatim: title)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrevSpacing.md) {
                    setupField(String(localized: "Host", bundle: .module)) {
                        TextField(String("mail.example.org"), text: host)
                    }

                    setupField(String(localized: "Port", bundle: .module)) {
                        TextField(String("993"), text: port)
                            .frame(width: 96)
                    }
                }

                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    setupField(String(localized: "Host", bundle: .module)) {
                        TextField(String("mail.example.org"), text: host)
                    }

                    setupField(String(localized: "Port", bundle: .module)) {
                        TextField(String("993"), text: port)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrevSpacing.md) {
                    securityPicker(selection: tlsMode)
                    authenticationPicker(selection: authentication)
                }

                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    securityPicker(selection: tlsMode)
                    authenticationPicker(selection: authentication)
                }
            }

            setupField(String(localized: "Username template", bundle: .module)) {
                TextField(String("%EMAILADDRESS%"), text: usernameTemplate)
            }
        }
        .setupSectionSurface(theme: theme)
    }

    private func securityPicker(
        selection: Binding<MailServerTLSMode>
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            fieldLabel(String(localized: "Security", bundle: .module))
            Picker(String(localized: "Security", bundle: .module), selection: selection) {
                Text(verbatim: "TLS").tag(MailServerTLSMode.implicit)
                Text(verbatim: "STARTTLS").tag(MailServerTLSMode.startTLS)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func authenticationPicker(
        selection: Binding<MailServerAuthentication>
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            fieldLabel(String(localized: "Authentication", bundle: .module))
            Picker(String(localized: "Authentication", bundle: .module), selection: selection) {
                ForEach(authenticationOptions, id: \.self) { option in
                    Text(verbatim: authenticationLabel(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func setupField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            fieldLabel(title)
            content()
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(verbatim: title)
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
    }

    private var discoverySummary: String {
        guard let discovery else {
            return String(localized: "Enter your email, then choose Find settings.", bundle: .module)
        }

        switch discovery.source {
        case .builtInProfile:
            return String(localized: "Found settings for \(discovery.displayName ?? discovery.domain).", bundle: .module)
        case .providerAutoconfig:
            return String(localized: "Found your provider's settings.", bundle: .module)
        case .dnsSRV:
            return String(localized: "Found settings from your domain's DNS records.", bundle: .module)
        case .dnsMXProvider:
            let providerName = discovery.displayName ?? String(localized: "your provider", bundle: .module)
            return String(localized: "Found \(providerName) from your domain's mail records.", bundle: .module)
        case .manualFallback:
            return String(
                localized: "Couldn't find settings automatically. Open Advanced setup to enter IMAP and SMTP details.",
                bundle: .module
            )
        }
    }

    private var serverFieldVisibility: IMAPAccountSetupPresentation.ServerFieldVisibility {
        IMAPAccountSetupPresentation.serverFieldVisibility(
            discovery: discovery,
            showServerFields: showServerFields,
            path: setupPath
        )
    }

    private var showsPasswordField: Bool {
        IMAPAccountSetupPresentation.showsPasswordField(
            path: setupPath,
            incomingAuthentication: incomingAuthentication
        )
    }

    private var showsAccountDetails: Bool {
        IMAPAccountSetupPresentation.showsAccountDetails(
            path: setupPath,
            isReauthentication: isReauthentication
        )
    }

    private var showsAdvancedServerFields: Bool {
        IMAPAccountSetupPresentation.showsAdvancedServerFields(
            isAdvancedSetupExpanded: isAdvancedSetupExpanded,
            visibility: serverFieldVisibility
        )
    }

    private var showsOAuthPrimary: Bool {
        IMAPAccountSetupPresentation.showsOAuthPrimary(
            path: setupPath,
            discovery: discovery,
            incomingAuthentication: incomingAuthentication
        )
    }

    private var showsGoogleAppPasswordSecondary: Bool {
        IMAPAccountSetupPresentation.showsGoogleAppPasswordSecondary(
            path: setupPath,
            discovery: discovery,
            incomingAuthentication: incomingAuthentication
        )
    }

    private var setupContentMaxWidth: CGFloat {
        #if os(iOS)
        560
        #else
        580
        #endif
    }

    private var canAddAccount: Bool {
        editedDiscovery != nil
            && IMAPAccountSetupPresentation.canSubmit(setupState)
    }

    private var canTestConnection: Bool {
        canAddAccount
            && session.canValidateIMAPAccountSetup
            && !session.isSigningIn
            && !isTestingConnection
    }

    private var canDiscoverSettings: Bool {
        IMAPAccountSetupPresentation.canDiscoverSettings(
            emailAddress: emailAddress,
            isDiscoveryAvailable: session.canDiscoverIMAPSettings
        )
    }

    private var setupState: IMAPAccountSetupPresentation.State {
        IMAPAccountSetupPresentation.State(
            emailAddress: emailAddress,
            password: password,
            incomingHost: incomingHost,
            incomingPort: incomingPort,
            incomingTLSMode: incomingTLSMode,
            incomingAuthentication: incomingAuthentication,
            incomingUsernameTemplate: incomingUsernameTemplate,
            outgoingHost: outgoingHost,
            outgoingPort: outgoingPort,
            outgoingTLSMode: outgoingTLSMode,
            outgoingAuthentication: outgoingAuthentication,
            outgoingUsernameTemplate: outgoingUsernameTemplate
        )
    }

    private var editedDiscovery: MailAccountDiscoveryResult? {
        guard var result = IMAPAccountSetupPresentation.editedDiscovery(
            state: setupState,
            baseDiscovery: discovery
        ) else {
            return nil
        }
        if isManageSieveEnabled {
            guard let manageSieveSettings else { return nil }
            result.manageSieve = manageSieveSettings
        }
        return result
    }

    private var oauthAction: IMAPAccountSetupPresentation.OAuthAction? {
        switch setupPath {
        case .google:
            return IMAPAccountSetupPresentation.oauthAction(
                for: .google,
                isOAuthSetupAvailable: session.canStartIMAPOAuthBrowserSetup,
                configuration: oauthConfiguration
            )
        case .outlook:
            return IMAPAccountSetupPresentation.oauthAction(
                for: .microsoft,
                isOAuthSetupAvailable: session.canStartIMAPOAuthBrowserSetup,
                configuration: oauthConfiguration
            )
        case .discovered, .manual, .undiscovered:
            guard let discovery else { return nil }
            return IMAPAccountSetupPresentation.oauthAction(
                for: discovery,
                isOAuthSetupAvailable: session.canStartIMAPOAuthBrowserSetup,
                configuration: oauthConfiguration
            )
        }
    }

    private var nativeExchangeGuidance: IMAPAccountSetupPresentation.NativeExchangeGuidance? {
        if setupPath == .outlook {
            let seed = discovery
                ?? IMAPAccountSetupPresentation.skipDiscovery(for: .outlook, emailAddress: emailAddress)
            guard let seed else { return nil }
            return IMAPAccountSetupPresentation.nativeExchangeGuidance(for: seed)
        }
        guard let discovery else { return nil }
        return IMAPAccountSetupPresentation.nativeExchangeGuidance(for: discovery)
    }

    private var authenticationOptions: [MailServerAuthentication] {
        [.password, .appPassword, .encryptedPassword, .xoauth2]
    }

    private var manageSieveSettings: MailServerSettings? {
        guard let port = UInt16(trimmed(manageSievePort)),
              !trimmed(manageSieveHost).isEmpty
        else {
            return nil
        }
        return MailServerSettings(
            kind: .imap,
            host: trimmed(manageSieveHost),
            port: port,
            tlsMode: manageSieveTLSMode,
            authentication: incomingAuthentication,
            usernameTemplate: incomingUsernameTemplate
        )
    }

    private var manageSieveEnabledBinding: Binding<Bool> {
        Binding(
            get: { isManageSieveEnabled },
            set: { isEnabled in
                isManageSieveEnabled = isEnabled
                if isEnabled, trimmed(manageSieveHost).isEmpty {
                    manageSieveHost = defaultManageSieveHost
                }
            }
        )
    }

    private var defaultManageSieveHost: String {
        let domain = emailAddress.split(separator: "@", maxSplits: 1).dropFirst().first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let domain, !domain.isEmpty else {
            return "sieve.example.org"
        }
        return "sieve.\(domain)"
    }

    private func authenticationLabel(_ authentication: MailServerAuthentication) -> String {
        switch authentication {
        case .password:
            return String(localized: "Password", bundle: .module)
        case .encryptedPassword:
            return String(localized: "Encrypted password", bundle: .module)
        case .appPassword:
            return String(localized: "App password", bundle: .module)
        case .xoauth2:
            return String(localized: "OAuth2", bundle: .module)
        case .none:
            return String(localized: "None", bundle: .module)
        }
    }

    /// Runs discovery only from Find settings (or one-shot re-auth).
    private func discover(asPath path: IMAPAccountSetupPresentation.SetupPath) {
        let email = trimmed(emailAddress)
        if let validationMessage = IMAPAccountSetupPresentation.discoveryValidationMessage(
            emailAddress: email,
            isDiscoveryAvailable: session.canDiscoverIMAPSettings
        ) {
            localStatus = SetupStatus(
                message: validationMessage,
                tone: .warning
            )
            focusedField = .email
            return
        }
        localStatus = nil
        didStartDiscoveryProbe = true
        isDiscovering = true
        Task {
            defer { isDiscovering = false }
            do {
                let result = try await session.discoverIMAPSettings(
                    forEmailAddress: email
                )
                applyDiscovery(result, path: path == .manual ? .manual : resolvedPath(for: result, preferred: path))
            } catch {
                applyDiscovery(
                    MailAccountAutodiscovery.manualFallback(forEmailAddress: email),
                    path: .manual
                )
                localStatus = SetupStatus(
                    message: AppSessionPresentation.signInErrorMessage(for: error),
                    tone: .warning
                )
            }
        }
    }

    private func applySkip(_ shortcut: IMAPAccountSetupPresentation.SkipShortcut) {
        let email = trimmed(emailAddress)
        if shortcut != .manual {
            guard MailAccountAutodiscovery.isValidEmailAddress(email) else {
                localStatus = SetupStatus(
                    message: String(
                        localized: "Enter a valid email address before skipping to \(shortcut.title).",
                        bundle: .module
                    ),
                    tone: .warning
                )
                focusedField = .email
                return
            }
        } else if email.isEmpty || !MailAccountAutodiscovery.isValidEmailAddress(email) {
            // Manual allows opening servers with a placeholder domain if needed.
            if !MailAccountAutodiscovery.isValidEmailAddress(email) {
                localStatus = SetupStatus(
                    message: String(localized: "Enter a valid email address before editing IMAP/SMTP settings.", bundle: .module),
                    tone: .warning
                )
                focusedField = .email
                return
            }
        }

        guard let result = IMAPAccountSetupPresentation.skipDiscovery(
            for: shortcut,
            emailAddress: email
        ) else {
            localStatus = SetupStatus(
                message: String(localized: "Could not load \(shortcut.title) settings.", bundle: .module),
                tone: .warning
            )
            return
        }

        let path: IMAPAccountSetupPresentation.SetupPath = switch shortcut {
        case .google: .google
        case .outlook: .outlook
        case .manual: .manual
        }
        didStartDiscoveryProbe = true
        applyDiscovery(result, path: path)
        if shortcut == .manual {
            showServerFields = true
        }
        localStatus = nil
    }

    private func useGoogleAppPassword() {
        incomingAuthentication = .appPassword
        outgoingAuthentication = .appPassword
        focusedField = .password
    }

    private func resolvedPath(
        for result: MailAccountDiscoveryResult,
        preferred: IMAPAccountSetupPresentation.SetupPath
    ) -> IMAPAccountSetupPresentation.SetupPath {
        if result.requiresManualReview {
            return .manual
        }
        if preferred == .discovered {
            return .discovered
        }
        return preferred
    }

    private func addAccount() {
        guard let discovery = editedDiscovery else {
            localStatus = SetupStatus(
                message: String(localized: "Review the IMAP and SMTP settings before adding the account.", bundle: .module),
                tone: .warning
            )
            return
        }
        localStatus = nil
        let request = IMAPAccountSetupPresentation.setupRequest(
            emailAddress: emailAddress,
            displayName: displayName,
            password: password,
            discovery: discovery
        )
        Task {
            await session.signIn(with: request)
            if session.signInError == nil,
               session.backend != nil {
                onClose()
            } else if let signInError = session.signInError {
                localStatus = SetupStatus(
                    message: IMAPAccountSetupPresentation.setupFailureMessage(
                        forSessionSignInError: signInError
                    ),
                    tone: .danger
                )
            }
        }
    }

    private func testConnection() {
        guard session.canValidateIMAPAccountSetup else {
            localStatus = SetupStatus(
                message: IMAPAccountSetupPresentation.connectionTestUnavailableMessage,
                tone: .warning
            )
            return
        }
        guard let discovery = editedDiscovery else {
            localStatus = SetupStatus(
                message: String(localized: "Review the IMAP and SMTP settings before testing the connection.", bundle: .module),
                tone: .warning
            )
            return
        }
        localStatus = nil
        isTestingConnection = true
        let request = IMAPAccountSetupPresentation.setupRequest(
            emailAddress: emailAddress,
            displayName: displayName,
            password: password,
            discovery: discovery
        )
        Task {
            defer { isTestingConnection = false }
            do {
                try await session.validateIMAPAccountSetup(request)
                localStatus = SetupStatus(
                    message: IMAPAccountSetupPresentation.connectionTestSuccessMessage,
                    tone: .success
                )
            } catch {
                localStatus = SetupStatus(
                    message: IMAPAccountSetupPresentation.connectionTestFailureMessage(for: error),
                    tone: .danger
                )
            }
        }
    }

    private func applyDiscovery(
        _ result: MailAccountDiscoveryResult,
        path: IMAPAccountSetupPresentation.SetupPath
    ) {
        discovery = result
        setupPath = path
        // Keep the common path clean: only auto-expand the server fields when
        // the result needs manual review or the user chose Manual.
        showServerFields = path == .manual || result.requiresManualReview
        if displayName.isEmpty,
           let discoveredName = result.displayName,
           path != .google, path != .outlook {
            // Don't overwrite with "Gmail"/"Outlook" brand from skip profiles.
            displayName = discoveredName
        }
        if let incoming = result.incoming {
            incomingHost = incoming.host
            incomingPort = String(incoming.port)
            incomingTLSMode = incoming.tlsMode
            incomingAuthentication = incoming.authentication
            incomingUsernameTemplate = incoming.usernameTemplate
        }
        if let outgoing = result.outgoing {
            outgoingHost = outgoing.host
            outgoingPort = String(outgoing.port)
            outgoingTLSMode = outgoing.tlsMode
            outgoingAuthentication = outgoing.authentication
            outgoingUsernameTemplate = outgoing.usernameTemplate
        }
        if let manageSieve = result.manageSieve {
            isManageSieveEnabled = true
            manageSieveHost = manageSieve.host
            manageSievePort = String(manageSieve.port)
            manageSieveTLSMode = manageSieve.tlsMode
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SetupStatus: Equatable {
    let message: String
    let tone: BrevInlineStatusTone
}

private extension View {
    @ViewBuilder
    func imapSetupTouchTarget() -> some View {
        #if os(iOS)
        frame(minHeight: 44)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }

    func setupSectionSurface(theme: BrevTheme) -> some View {
        padding(BrevSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgSecondary.color)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .stroke(theme.border.color, lineWidth: 1)
            }
    }
}
