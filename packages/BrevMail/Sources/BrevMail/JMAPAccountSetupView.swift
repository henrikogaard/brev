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
import BrevJMAP
import BrevThemes
import SwiftUI

/// Account setup surface for connecting a native RFC 8620 / RFC 8621 JMAP mailbox
/// (such as Fastmail, Stalwart, or Cyrus) with Keychain-only API token storage.
public struct JMAPAccountSetupView: View {
    @Environment(\.brevTheme) private var theme
    @Bindable private var session: AppSession

    @State private var selectedPreset: JMAPServerPreset
    @State private var sessionURLString: String
    @State private var emailAddress: String
    @State private var displayName: String
    @State private var bearerToken: String
    @State private var localErrorMessage: String?

    private let onClose: () -> Void
    private let isReauthentication: Bool

    /// Creates a JMAP account setup view.
    ///
    /// - Parameters:
    ///   - session: Active `AppSession` owning the JMAP setup coordinator.
    ///   - initialPreset: Default provider preset (`.fastmail` by default).
    ///   - initialEmailAddress: Optional email prefill (non-empty enters token-update mode).
    ///   - initialSessionURL: Optional custom session URL override.
    ///   - onClose: Invoked when the user cancels or completes setup.
    public init(
        session: AppSession,
        initialPreset: JMAPServerPreset = .fastmail,
        initialEmailAddress: String = "",
        initialSessionURL: String? = nil,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        _selectedPreset = State(initialValue: initialPreset)
        _sessionURLString = State(
            initialValue: initialSessionURL ?? initialPreset.defaultSessionURLString
        )
        _emailAddress = State(initialValue: initialEmailAddress)
        _displayName = State(initialValue: "")
        _bearerToken = State(initialValue: "")
        self.onClose = onClose
        isReauthentication = !initialEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        #if os(iOS)
        NavigationStack {
            setupContent
                .navigationTitle(setupTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", bundle: .module)) {
                            onClose()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(
                            session.isSigningIn
                                ? String(localized: "Connecting", bundle: .module)
                                : String(localized: "Connect", bundle: .module)
                        ) {
                            connectAccount()
                        }
                        .disabled(!canSubmit || session.isSigningIn)
                    }
                }
        }
        #else
        setupContent
        #endif
    }

    private var setupContent: some View {
        platformLayout
            .background(theme.bgPrimary.color)
            .onChange(of: session.signInError) { _, error in
                if let error {
                    localErrorMessage = error
                }
            }
    }

    @ViewBuilder
    private var platformLayout: some View {
        #if os(iOS)
        ScrollView {
            scrollableContent
                .padding(.horizontal, BrevSpacing.lg)
                .padding(.vertical, BrevSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let errorMessage = activeErrorMessage {
                BrevInlineStatus(message: errorMessage, tone: .danger, lineLimit: nil)
                    .padding(.horizontal, BrevSpacing.lg)
                    .padding(.vertical, BrevSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(theme.bgPrimary.color)
            }
        }
        #else
        VStack(spacing: BrevSpacing.lg) {
            ScrollView {
                scrollableContent
            }

            if let errorMessage = activeErrorMessage {
                BrevInlineStatus(message: errorMessage, tone: .danger, lineLimit: nil)
                    .frame(maxWidth: setupContentMaxWidth, alignment: .leading)
            }

            macActions
                .frame(maxWidth: setupContentMaxWidth)
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.xl)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440)
        #endif
    }

    private var scrollableContent: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            header
            presetSelectorCard
            credentialsCard
        }
        .frame(maxWidth: setupContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var setupTitle: String {
        if isReauthentication {
            String(localized: "Update JMAP API token", bundle: .module)
        } else {
            String(localized: "Add JMAP account", bundle: .module)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .top, spacing: BrevSpacing.md) {
                BrevBrandIcon(size: 32, cornerRadius: BrevRadius.sm)
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    #if os(macOS)
                    Text(verbatim: setupTitle)
                        .brevFont(.title)
                        .foregroundStyle(theme.textPrimary.color)
                    #endif
                    Text(
                        "Connect Fastmail, Stalwart, Cyrus, or any standards-compliant JMAP server.",
                        bundle: .module
                    )
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Label {
                Text(
                    "Your API token stays in Keychain and is sent only to your JMAP server over HTTPS.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
                    .foregroundStyle(theme.textTertiary.color)
            }
        }
    }

    private var presetSelectorCard: some View {
        setupCard {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                Text("JMAP provider", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)

                HStack(spacing: BrevSpacing.sm) {
                    presetButton(
                        title: String(localized: "Fastmail", bundle: .module),
                        subtitle: String(localized: "api.fastmail.com", bundle: .module),
                        preset: .fastmail
                    )
                    presetButton(
                        title: String(localized: "Custom JMAP server", bundle: .module),
                        subtitle: String(localized: "Stalwart, Cyrus, or self-hosted", bundle: .module),
                        preset: .custom
                    )
                }

                setupField(String(localized: "JMAP session URL or domain", bundle: .module)) {
                    TextField(
                        String("https://mail.example.org/.well-known/jmap"),
                        text: $sessionURLString
                    )
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    #endif
                }

                Text(
                    "Requires HTTPS. Enter an explicit session URL or a domain for /.well-known/jmap discovery.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func presetButton(
        title: String,
        subtitle: String,
        preset: JMAPServerPreset
    ) -> some View {
        let isSelected = selectedPreset == preset
        return Button {
            selectPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                HStack(spacing: BrevSpacing.xs) {
                    Text(verbatim: title)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .brevFont(.caption)
                            .foregroundStyle(theme.accent.color)
                            .accessibilityHidden(true)
                    }
                }
                Text(verbatim: subtitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                    .fill(isSelected ? theme.selection.color : theme.bgPrimary.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent.color : theme.border.color, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var credentialsCard: some View {
        setupCard {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                setupField(String(localized: "Email address", bundle: .module)) {
                    TextField(
                        selectedPreset == .fastmail
                            ? String("name@fastmail.com")
                            : String("name@example.org"),
                        text: $emailAddress
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(isReauthentication)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    #endif
                }

                setupField(String(localized: "Display name (optional)", bundle: .module)) {
                    TextField(
                        String(localized: "Name shown on the account", bundle: .module),
                        text: $displayName
                    )
                    .textFieldStyle(.roundedBorder)
                }

                setupField(String(localized: "API token", bundle: .module)) {
                    SecureField(
                        String(localized: "Stored locally in Keychain", bundle: .module),
                        text: $bearerToken
                    )
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                        .textContentType(.password)
                    #endif
                }

                Text(
                    "Create an app-specific API token with mail access in your JMAP provider settings.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    #if os(macOS)
    private var macActions: some View {
        HStack(spacing: BrevSpacing.sm) {
            BrevButton("Cancel", style: .secondary, bundle: .module) {
                onClose()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            BrevButton(
                session.isSigningIn ? "Connecting" : "Add JMAP account",
                style: .primary,
                bundle: .module
            ) {
                connectAccount()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit || session.isSigningIn)
        }
    }
    #endif

    private func setupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md, content: content)
            .padding(BrevSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous)
                    .fill(theme.bgSecondary.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous)
                    .strokeBorder(theme.border.color, lineWidth: 1)
            )
    }

    private func setupField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(verbatim: label)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            content()
        }
    }

    private var setupContentMaxWidth: CGFloat { 520 }

    private var activeErrorMessage: String? {
        if let localErrorMessage { return localErrorMessage }
        let trimmedURL = sessionURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            do {
                _ = try JMAPURLValidator.discoveryURL(from: trimmedURL)
            } catch {
                return error.localizedDescription
            }
        }
        return session.signInError
    }

    private var canSubmit: Bool {
        let trimmedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = sessionURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), !trimmedToken.isEmpty, !trimmedURL.isEmpty else {
            return false
        }
        return (try? JMAPURLValidator.discoveryURL(from: trimmedURL)) != nil
    }

    private func selectPreset(_ preset: JMAPServerPreset) {
        selectedPreset = preset
        localErrorMessage = nil
        switch preset {
        case .fastmail:
            sessionURLString = preset.defaultSessionURLString
        case .custom:
            if sessionURLString == JMAPServerPreset.fastmail.defaultSessionURLString {
                sessionURLString = ""
            }
        }
    }

    private func connectAccount() {
        localErrorMessage = nil
        let trimmedURL = sessionURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try JMAPURLValidator.discoveryURL(from: trimmedURL)
        } catch {
            localErrorMessage = error.localizedDescription
            return
        }
        let request = JMAPAccountSetupRequest(
            emailAddress: emailAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionURLString: trimmedURL,
            bearerToken: bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Task { @MainActor in
            await session.signIn(with: request)
            if session.signInError == nil, session.backend != nil {
                onClose()
            }
        }
    }
}
