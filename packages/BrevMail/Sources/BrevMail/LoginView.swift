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

import BrevDesign
import BrevThemes
import SwiftUI

/// Brev-styled landing view shown when no account is signed in.
/// Account setup is driven by `AppSession.signIn()` when the app
/// target injects an interactive `LoginCoordinator`.
public struct LoginView: View {
    @Environment(\.brevTheme) private var theme
    @Bindable private var session: AppSession
    @State private var isShowingIMAPSetup = false
    @State private var authenticationTask: Task<Void, Never>?
    @State private var nextAuthenticationTaskRequestID = 0
    @State private var activeAuthenticationTaskRequest: AuthenticationTaskRequest?
    private let onAddAccount: (() -> Void)?

    public init(session: AppSession, onAddAccount: (() -> Void)? = nil) {
        self.session = session
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = LoginViewPresentation.layout(for: proxy.size.width)

            ZStack {
                BrevWindowSurfaceBackground(role: .mainWindow)
                    .ignoresSafeArea()

                ScrollView {
                    Group {
                        if layout == .wide {
                            wideContent
                        } else {
                            compactContent
                        }
                    }
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, layout == .wide ? BrevSpacing.xxl : BrevSpacing.xl)
                    .padding(.vertical, BrevSpacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .brevWindowTranslucency(windowRole: .mainWindow)
        .sheet(isPresented: $isShowingIMAPSetup) {
            if let failedEmail = session.authFailedIMAPAccountEmail {
                IMAPAccountSetupSheet(
                    session: session,
                    initialEmailAddress: failedEmail,
                    onClose: { isShowingIMAPSetup = false }
                )
                .brevTheme(theme)
            } else {
                MailAccountSetupSheet(
                    session: session,
                    onClose: { isShowingIMAPSetup = false }
                )
                .brevTheme(theme)
            }
        }
    }

    // MARK: - Responsive composition

    private var wideContent: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxl) {
            wordmark(iconSize: 52)

            HStack(alignment: .top, spacing: BrevSpacing.xxl) {
                welcomeCopy
                    .frame(maxWidth: 300, alignment: .leading)

                accountConnectionSection
                    .frame(maxWidth: 360, alignment: .leading)
            }
        }
        .frame(maxWidth: 760, minHeight: 460, alignment: .center)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xl) {
            wordmark(iconSize: 48)
            welcomeCopy
            accountConnectionSection
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    // MARK: - Brand and account setup

    private func wordmark(iconSize: CGFloat) -> some View {
        HStack(spacing: BrevSpacing.md) {
            BrevBrandIcon(size: iconSize, cornerRadius: BrevRadius.md)

            Text(verbatim: "Brev")
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "Brev"))
    }

    private var welcomeCopy: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Text("Connect your mailbox.", bundle: .module)
                .brevFont(.largeTitle)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "Gmail, Google Workspace, and standard IMAP accounts in one place.",
                bundle: .module
            )
            .brevFont(.body)
            .foregroundStyle(theme.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountConnectionSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xl) {
            restoreFailureStatus

            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                Text(connectionSectionTitle, bundle: .module)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)

                if session.signInError != nil {
                    Text("Repair the saved account or choose another sign-in method.", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            accountSetupSection
            secondaryActions
            privacyNote
        }
    }

    private var connectionSectionTitle: LocalizedStringKey {
        session.signInError == nil ? "Choose how to connect" : "Reconnect your mailbox"
    }

    @ViewBuilder
    private var accountSetupSection: some View {
        if session.canUseIMAPAccountSetup || session.canUseInteractiveSignIn || session.canStartGoogleSignIn {
            accountSetupControls
        } else {
            Text(
                "Mail account setup is not available in this build. Use the demo mailbox for local UI testing.",
                bundle: .module
            )
            .brevFont(.caption)
            .foregroundStyle(theme.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountSetupControls: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xl) {
            if session.canStartGoogleSignIn {
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    BrevButton("Continue with Google", bundle: .module) {
                        startAuthentication {
                            await session.signInWithIMAPOAuthProvider(.google)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAuthenticationActionBlocked)
                    .loginTouchTarget()

                    Text(googleConnectionDescription, bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if session.canUseIMAPAccountSetup || session.canUseInteractiveSignIn {
                    VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                        BrevButton(
                            "Use another mail account",
                            style: .secondary,
                            bundle: .module,
                            action: startAccountSetup
                        )
                        .disabled(isAuthenticationActionBlocked)
                        .loginTouchTarget()

                        Text("For Fastmail and other IMAP/SMTP providers.", bundle: .module)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                BrevButton("Add mail account", bundle: .module, action: startAccountSetup)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAuthenticationActionBlocked)
                    .loginTouchTarget()

                Text(
                    "Brev finds IMAP and SMTP settings from your email, or lets you enter them yourself.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            }

            if isAuthenticationActionBlocked {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BrevSpacing.sm) {
                        connectingStatusLabel
                        cancelSignInButton
                    }

                    VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                        connectingStatusLabel
                        cancelSignInButton
                    }
                }
            }
        }
    }

    private var googleConnectionDescription: LocalizedStringKey {
        if session.canStartNativeGoogleSignIn {
            "Uses Google's secure sign-in and the Gmail API."
        } else {
            "Uses Google's secure sign-in to connect this mailbox."
        }
    }

    private func startAccountSetup() {
        if session.canUseIMAPAccountSetup {
            if let onAddAccount {
                onAddAccount()
            } else {
                isShowingIMAPSetup = true
            }
        } else if session.canUseInteractiveSignIn {
            startAuthentication {
                await session.signIn()
            }
        }
    }

    private var connectingStatusLabel: some View {
        Label {
            Text("Connecting to your mailbox…", bundle: .module)
        } icon: {
            ProgressView()
                .controlSize(.small)
        }
        .brevFont(.caption)
        .foregroundStyle(theme.textSecondary.color)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var cancelSignInButton: some View {
        if session.isSigningIn {
            BrevButton("Cancel sign-in", style: .tertiary, bundle: .module) {
                cancelAuthentication()
            }
            .loginTouchTarget()
        }
    }

    private func startAuthentication(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        authenticationTask?.cancel()
        nextAuthenticationTaskRequestID += 1
        let request = AuthenticationTaskRequest(id: nextAuthenticationTaskRequestID)
        activeAuthenticationTaskRequest = request
        authenticationTask = Task { @MainActor in
            await operation()
            guard AuthenticationTaskResponsePolicy.canClear(
                completedRequest: request,
                activeRequest: activeAuthenticationTaskRequest
            ) else { return }
            activeAuthenticationTaskRequest = nil
            authenticationTask = nil
        }
    }

    private func cancelAuthentication() {
        activeAuthenticationTaskRequest = nil
        authenticationTask?.cancel()
        authenticationTask = nil
        session.cancelSignIn()
    }

    // MARK: - Secondary actions

    @ViewBuilder
    private var restoreFailureStatus: some View {
        if let error = session.signInError {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                BrevInlineStatus(
                    message: error,
                    tone: .danger,
                    actionTitle: restoreFailureActionTitle,
                    onAction: restoreFailureAction,
                    lineLimit: nil
                )
                .loginTouchTarget()

                if let guidance = IMAPAccountSetupPresentation.reauthenticationGuidance(
                    emailAddress: session.authFailedIMAPAccountEmail
                ) {
                    BrevInlineStatus(
                        message: guidance,
                        tone: .info,
                        lineLimit: nil
                    )
                    .loginTouchTarget()
                }
            }
            .frame(maxWidth: 400)
        }
    }

    private var restoreFailureActionTitle: String? {
        switch LoginViewPresentation.recoveryAction(
            failedEmail: session.authFailedIMAPAccountEmail,
            canRetry: session.canRetrySessionRestore,
            canUseGoogleIMAPFallback: session.canUseGoogleIMAPFallback
        ) {
        case .googleIMAPFallback:
            return String(localized: "Use Google IMAP/SMTP instead", bundle: .module)
        case .updatePassword:
            return String(localized: "Update password", bundle: .module)
        case .retry:
            return String(localized: "Retry", bundle: .module)
        case nil:
            return nil
        }
    }

    private var restoreFailureAction: (() -> Void)? {
        switch LoginViewPresentation.recoveryAction(
            failedEmail: session.authFailedIMAPAccountEmail,
            canRetry: session.canRetrySessionRestore,
            canUseGoogleIMAPFallback: session.canUseGoogleIMAPFallback
        ) {
        case .googleIMAPFallback:
            return {
                startAuthentication {
                    await session.signInWithGoogleIMAPFallback()
                }
            }
        case .updatePassword:
            return { isShowingIMAPSetup = true }
        case .retry:
            return { Task { await session.restoreAllAccounts() } }
        case nil:
            return nil
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        if session.canUseDemoAccount {
            BrevButton("Preview Brev with sample mail", style: .tertiary, bundle: .module) {
                Task { await session.signInWithDemo() }
            }
            .disabled(isAuthenticationActionBlocked)
            .loginTouchTarget()
            .accessibilityHint(Text("Opens a local sample mailbox without connecting an account.", bundle: .module))
        }
    }

    // MARK: - Privacy

    private var privacyNote: some View {
        Label {
            Text(
                "Your credentials stay in the Keychain. Brev connects directly to your mail provider.",
                bundle: .module
            )
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill")
                .foregroundStyle(theme.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }

    private var isAuthenticationActionBlocked: Bool {
        session.isSigningIn || session.isRestoringSession || session.isSigningOut
    }
}

/// The Brev app-icon tile rendered as an in-UI brand mark from the package's
/// shared asset catalog. Used on welcome and account-setup surfaces instead of
/// a generic envelope SF Symbol.
struct BrevBrandIcon: View {
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        Image(LoginViewPresentation.brandIconAssetName, bundle: .module)
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

public enum LoginViewPresentation {
    /// The two compositions used by the adaptive onboarding surface.
    public enum Layout: Equatable, Sendable {
        case compact
        case wide
    }

    /// The single repair action shown for a failed session restore.
    public enum RecoveryAction: Equatable, Sendable {
        case googleIMAPFallback
        case updatePassword
        case retry
    }

    /// Width at which the onboarding has enough room for brand and actions
    /// to sit side by side without compromising readability.
    public static func layout(for width: CGFloat) -> Layout {
        width >= 700 ? .wide : .compact
    }

    /// Chooses one recovery action so a failed restore never presents duplicate
    /// retry/update controls.
    public static func recoveryAction(
        failedEmail: String?,
        canRetry: Bool,
        canUseGoogleIMAPFallback: Bool = false
    ) -> RecoveryAction? {
        if canUseGoogleIMAPFallback {
            return .googleIMAPFallback
        }
        if failedEmail != nil {
            return .updatePassword
        }
        if canRetry {
            return .retry
        }
        return nil
    }

    /// Package resource name of the Brev app-icon tile shown as the
    /// welcome-screen brand mark.
    public static let brandIconAssetName = "BrevIconEnvelopeLightPreview"
}

private extension View {
    @ViewBuilder
    func loginTouchTarget() -> some View {
        #if os(iOS)
        frame(minHeight: 44)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }
}
