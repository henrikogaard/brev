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

import BrevAI
import BrevAvatars
import BrevDesign
import BrevThemes
import SwiftUI

/// Optional plain-language walkthrough letting users opt into privacy-sensitive conveniences
/// without silently enabling any external network call or AI feature.
public struct PrivacyOnboardingSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var choices: PrivacyOnboardingChoices

    private let mode: PrivacyOnboardingMode
    private let initialChoices: PrivacyOnboardingChoices
    private let settingsStore: SettingsPersistenceStore
    private let appleIntelligenceAvailability: AppleIntelligenceAvailability
    private let isRichHTMLRendererEnabled: Bool
    private let stripTrackingPixelsEnabled: Bool
    private let onDeviceAIBlockReason: PrivacyOnboardingAIControlBlockReason?
    private let onAIProviderConfigurationChanged: () async -> Void
    private let onAvatarPreferencesChanged: @Sendable (AvatarPreferences) async -> Void
    private let onDismiss: () -> Void

    /// Creates the Privacy & Convenience Choices walkthrough sheet.
    ///
    /// Resolves `BrevAI` and `BrevAvatars` defaults inside `BrevSettings` so callers such as
    /// `BrevIOS` do not emit direct linker references to transitive packages.
    ///
    /// - Parameters:
    ///   - mode: Whether the sheet runs after first-run setup or is reopened from Settings.
    ///   - settingsStore: Persistence boundary backing the toggles.
    ///   - onAIProviderConfigurationChanged: Callback invoked when on-device AI settings change.
    ///   - onDismiss: Callback invoked after saving, keeping defaults, or cancelling.
    public init(
        mode: PrivacyOnboardingMode = .firstRun,
        settingsStore: SettingsPersistenceStore = .standard,
        onAIProviderConfigurationChanged: @escaping () async -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.init(
            mode: mode,
            settingsStore: settingsStore,
            appleIntelligenceAvailability: .current(),
            onAIProviderConfigurationChanged: onAIProviderConfigurationChanged,
            onAvatarPreferencesChanged: { preferences in
                await AvatarResolver.shared.updatePreferences(preferences)
            },
            onDismiss: onDismiss
        )
    }

    init(
        mode: PrivacyOnboardingMode = .firstRun,
        settingsStore: SettingsPersistenceStore = .standard,
        appleIntelligenceAvailability: AppleIntelligenceAvailability,
        onAIProviderConfigurationChanged: @escaping () async -> Void = {},
        onAvatarPreferencesChanged: @escaping @Sendable (AvatarPreferences) async -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.settingsStore = settingsStore
        self.appleIntelligenceAvailability = appleIntelligenceAvailability
        self.onAIProviderConfigurationChanged = onAIProviderConfigurationChanged
        self.onAvatarPreferencesChanged = onAvatarPreferencesChanged
        self.onDismiss = onDismiss
        let mailboxView = settingsStore.mailboxViewSettings()
        isRichHTMLRendererEnabled = mailboxView.useRichRenderer
        stripTrackingPixelsEnabled = mailboxView.stripTrackingPixels
        onDeviceAIBlockReason = PrivacyOnboardingChoices.onDeviceAIBlockReason(in: settingsStore)
        let loaded = PrivacyOnboardingChoices.load(
            from: settingsStore,
            appleIntelligenceAvailability: appleIntelligenceAvailability
        )
        initialChoices = loaded
        _choices = State(initialValue: loaded)
    }

    public var body: some View {
        #if os(iOS)
        iOSBody
        #else
        macOSBody
        #endif
    }

    // MARK: - Platform Chrome

    #if os(macOS)
    private var macOSBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, BrevSpacing.xl)
                .padding(.top, BrevSpacing.xl)
                .padding(.bottom, BrevSpacing.lg)

            Divider()
                .overlay(theme.border.color)

            ScrollView {
                cardsStack
                    .padding(.horizontal, BrevSpacing.xl)
                    .padding(.vertical, BrevSpacing.lg)
            }
            .scrollIndicators(.visible, axes: .vertical)

            Divider()
                .overlay(theme.border.color)

            footerBar
                .padding(.horizontal, BrevSpacing.xl)
                .padding(.vertical, BrevSpacing.md)
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 540, idealHeight: 680)
        .background(theme.bgPrimary.color)
    }
    #endif

    #if os(iOS)
    private var iOSBody: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                        headerSection
                        cardsStack
                        if dynamicTypeSize.isAccessibilitySize {
                            Divider()
                                .overlay(theme.border.color)
                            footerBar
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? BrevSpacing.md : BrevSpacing.lg)
                    .padding(.vertical, BrevSpacing.lg)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Divider()
                        .overlay(theme.border.color)

                    footerBar
                        .padding(.horizontal, BrevSpacing.lg)
                        .padding(.vertical, BrevSpacing.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.bgPrimary.color.ignoresSafeArea())
            .navigationTitle(Text("Privacy & Convenience", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        handleSecondaryAction()
                    } label: {
                        Text(mode == .firstRun ? "Skip" : "Cancel", bundle: .module)
                    }
                }
            }
        }
    }
    #endif

    // MARK: - Header & Footer

    @ViewBuilder
    private var headerSection: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                headerIconBadge
                headerTextColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: BrevSpacing.md) {
                headerIconBadge
                headerTextColumn
            }
        }
    }

    private var headerIconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                .fill(theme.bgSecondary.color)
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                        .strokeBorder(theme.border.color, lineWidth: 1)
                )
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.accent.color)
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    private var headerTextColumn: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text("Privacy & Convenience Choices", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerSubtitle)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .firstRun:
            String(
                localized: "Every optional feature starts off. Turn on only the conveniences you want — you can change these anytime in Settings → Privacy.",
                bundle: .module
            )
        case .reviewFromSettings:
            String(
                localized: "Review your current opt-in conveniences. Unchanged choices stay as they are, and Cancel discards edits.",
                bundle: .module
            )
        }
    }

    @ViewBuilder
    private var footerBar: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: BrevSpacing.sm) {
                accessibilityFooterButton(
                    title: String(localized: "Save choices", bundle: .module),
                    isPrimary: true,
                    action: handleSave
                )
                .keyboardShortcut(.defaultAction)

                accessibilityFooterButton(
                    title: mode == .firstRun
                        ? String(localized: "Keep defaults (all off)", bundle: .module)
                        : String(localized: "Cancel", bundle: .module),
                    isPrimary: false,
                    action: handleSecondaryAction
                )
                .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrevSpacing.sm) {
                    secondaryActionButton
                    Spacer(minLength: BrevSpacing.md)
                    primaryActionButton
                }
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    primaryActionButton
                    secondaryActionButton
                }
            }
        }
    }

    private func accessibilityFooterButton(
        title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .brevFont(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BrevSpacing.md)
                .padding(.vertical, BrevSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isPrimary ? theme.accent.color : Color.clear)
                .foregroundStyle(isPrimary ? theme.onAccent.color : theme.textPrimary.color)
                .overlay {
                    if !isPrimary {
                        RoundedRectangle(cornerRadius: BrevRadius.md)
                            .stroke(theme.controlBorder.color, lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
                .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        }
        .buttonStyle(.plain)
    }

    private var secondaryActionButton: some View {
        BrevButton(
            verbatim: mode == .firstRun
                ? String(localized: "Keep defaults (all off)", bundle: .module)
                : String(localized: "Cancel", bundle: .module),
            style: .secondary
        ) {
            handleSecondaryAction()
        }
        .keyboardShortcut(.cancelAction)
    }

    private var primaryActionButton: some View {
        BrevButton(
            verbatim: String(localized: "Save choices", bundle: .module),
            style: .primary
        ) {
            handleSave()
        }
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Cards

    private var cardsStack: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            senderAvatarsCard
            trustedSendersCard
            iCloudSyncCard
            backgroundMailAndIndexingCard
            onDeviceAICard
        }
    }

    private var senderAvatarsCard: some View {
        PrivacyOnboardingCard(
            symbolName: "person.crop.circle",
            title: String(localized: "Sender Avatars", bundle: .module),
            scopeBadge: String(localized: "External lookup", bundle: .module),
            scopeTone: .network
        ) {
            PrivacyOnboardingToggleRow(
                title: String(localized: "Brand logos & domain icons", bundle: .module),
                subtitle: String(
                    localized: "Checks BIMI DNS records and fetches favicons from sender domains during sync. Never shares sender email addresses with a third party.",
                    bundle: .module
                ),
                isOn: $choices.useDomainAvatars
            )

            Divider()
                .overlay(theme.separator.color)

            PrivacyOnboardingToggleRow(
                title: String(localized: "Gravatar avatars", bundle: .module),
                subtitle: String(
                    localized: "Sends a SHA-256 hash of each sender’s email address to gravatar.com to fetch a profile photo.",
                    bundle: .module
                ),
                isOn: $choices.useGravatar
            )
        }
    }

    private var trustedSendersCard: some View {
        PrivacyOnboardingCard(
            symbolName: "photo.badge.checkmark",
            title: String(localized: "Trusted-Sender Remote Images", bundle: .module),
            scopeBadge: String(localized: "Trusted senders only", bundle: .module),
            scopeTone: .network
        ) {
            PrivacyOnboardingToggleRow(
                title: String(localized: "Load remote images for trusted senders", bundle: .module),
                subtitle: PrivacyOnboardingCopy.trustedSendersSubtitle(
                    useRichRenderer: isRichHTMLRendererEnabled,
                    stripTrackingPixels: stripTrackingPixelsEnabled
                ),
                isOn: trustedSendersBinding,
                isEnabled: isRichHTMLRendererEnabled
            )
        }
    }

    private var trustedSendersBinding: Binding<Bool> {
        Binding(
            get: { isRichHTMLRendererEnabled && choices.allowRemoteContentForTrustedSenders },
            set: { newValue in
                guard isRichHTMLRendererEnabled else { return }
                choices.allowRemoteContentForTrustedSenders = newValue
            }
        )
    }

    private var iCloudSyncCard: some View {
        PrivacyOnboardingCard(
            symbolName: "icloud",
            title: String(localized: "iCloud Preference Sync", bundle: .module),
            scopeBadge: String(localized: "Your Apple ID", bundle: .module),
            scopeTone: .network
        ) {
            PrivacyOnboardingToggleRow(
                title: String(localized: "Sync preferences with iCloud", bundle: .module),
                subtitle: String(
                    localized: "Mirrors non-secret preferences (VIPs, signatures, snoozes, smart views, compose and sidebar settings) via your iCloud Key-Value Storage. Never syncs mail bodies or credentials.",
                    bundle: .module
                ),
                isOn: $choices.iCloudPreferenceSyncEnabled
            )
        }
    }

    private var backgroundMailAndIndexingCard: some View {
        PrivacyOnboardingCard(
            symbolName: "arrow.triangle.2.circlepath",
            title: String(localized: "Background Mail & Search Indexing", bundle: .module),
            scopeBadge: String(localized: "Your mail server only", bundle: .module),
            scopeTone: .mailServer
        ) {
            #if os(macOS)
            PrivacyOnboardingToggleRow(
                title: String(localized: "Keep checking mail in the background", bundle: .module),
                subtitle: String(
                    localized: "Keeps checking your configured mail servers when no window is open and shows status in the menu bar.",
                    bundle: .module
                ),
                isOn: $choices.backgroundMailEnabled
            )

            Divider()
                .overlay(theme.separator.color)
            #endif

            PrivacyOnboardingToggleRow(
                title: String(localized: "Index recent mail & attachments in background", bundle: .module),
                subtitle: String(
                    localized: "Politely indexes recent message bodies and eligible text attachments on this device for instant offline search. Wi-Fi & power friendly; excludes Trash and Spam.",
                    bundle: .module
                ),
                isOn: $choices.backgroundIndexingEnabled
            )
        }
    }

    private var canToggleOnDeviceAI: Bool {
        appleIntelligenceAvailability.isSelectable && onDeviceAIBlockReason == nil
    }

    private var onDeviceAICard: some View {
        PrivacyOnboardingCard(
            symbolName: "cpu",
            title: String(localized: "On-Device AI", bundle: .module),
            scopeBadge: String(localized: "On-device · Zero network", bundle: .module),
            scopeTone: .onDevice
        ) {
            PrivacyOnboardingToggleRow(
                title: String(localized: "Enable on-device Apple Intelligence", bundle: .module),
                subtitle: onDeviceAISubtitle,
                isOn: onDeviceAIBinding,
                isEnabled: canToggleOnDeviceAI
            )

            Divider()
                .overlay(theme.separator.color)

            PrivacyOnboardingToggleRow(
                title: String(localized: "Automatic on-device summaries & priority", bundle: .module),
                subtitle: String(
                    localized: "Generates short local thread summaries and Urgent or Needs reply badges from cached mail only. Never contacts any server.",
                    bundle: .module
                ),
                isOn: proactiveTriageBinding,
                isEnabled: canToggleOnDeviceAI && choices.onDeviceAIEnabled
            )
        }
    }

    private var onDeviceAISubtitle: String {
        guard appleIntelligenceAvailability.isSelectable else {
            return appleIntelligenceAvailability.settingsStatusMessage
        }
        if let onDeviceAIBlockReason {
            return onDeviceAIBlockReason.message
        }
        return String(
            localized: "Runs AI Writer, thread summaries, and mailbox Assistant locally (\(OnDeviceAIPlatformLabel.transparencyLabel)) with zero network calls and no API key. Cloud and custom providers are never configured here.",
            bundle: .module
        )
    }

    private var onDeviceAIBinding: Binding<Bool> {
        Binding(
            get: { appleIntelligenceAvailability.isSelectable && choices.onDeviceAIEnabled },
            set: { newValue in
                guard canToggleOnDeviceAI else { return }
                choices.onDeviceAIEnabled = newValue
                if !newValue {
                    choices.proactiveOnDeviceTriageEnabled = false
                }
            }
        )
    }

    private var proactiveTriageBinding: Binding<Bool> {
        Binding(
            get: {
                appleIntelligenceAvailability.isSelectable
                    && choices.onDeviceAIEnabled
                    && choices.proactiveOnDeviceTriageEnabled
            },
            set: { newValue in
                guard canToggleOnDeviceAI && choices.onDeviceAIEnabled else { return }
                choices.proactiveOnDeviceTriageEnabled = newValue
            }
        )
    }

    // MARK: - Actions

    private func handleSecondaryAction() {
        if mode == .firstRun {
            PrivacyOnboardingChoices.keepPrivacyDefaults(in: settingsStore)
        }
        onDismiss()
    }

    private func handleSave() {
        let result = choices.apply(
            to: settingsStore,
            relativeTo: initialChoices,
            appleIntelligenceAvailability: appleIntelligenceAvailability
        )
        if let updatedAvatars = result.updatedAvatarPreferences {
            let updateHandler = onAvatarPreferencesChanged
            Task {
                await updateHandler(updatedAvatars)
            }
        }
        if result.aiConfigurationChanged {
            let reloadHandler = onAIProviderConfigurationChanged
            Task {
                await reloadHandler()
            }
        }
        onDismiss()
    }
}

private enum PrivacyOnboardingScopeTone {
    case onDevice
    case mailServer
    case network
}

private struct PrivacyOnboardingCard<Content: View>: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let symbolName: String
    let title: String
    let scopeBadge: String
    let scopeTone: PrivacyOnboardingScopeTone
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            cardHeader

            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                content
            }
        }
        .padding(BrevSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brevQuietSurface(cornerRadius: BrevRadius.md)
    }

    @ViewBuilder
    private var cardHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedCardHeader(allowsBadgeWrapping: true)
        } else {
            #if os(iOS)
            ViewThatFits(in: .horizontal) {
                inlineCardHeader
                stackedCardHeader(allowsBadgeWrapping: true)
            }
            #else
            inlineCardHeader
            #endif
        }
    }

    private var inlineCardHeader: some View {
        HStack(alignment: .center, spacing: BrevSpacing.sm) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)

            Text(title)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: BrevSpacing.sm)

            scopeBadgeView(allowsWrapping: false)
        }
    }

    private func stackedCardHeader(allowsBadgeWrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
                Image(systemName: symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent.color)
                    .accessibilityHidden(true)

                Text(title)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            scopeBadgeView(allowsWrapping: allowsBadgeWrapping)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func scopeBadgeView(allowsWrapping: Bool) -> some View {
        if allowsWrapping {
            Text(scopeBadge)
                .brevFont(.caption)
                .foregroundStyle(scopeForegroundColor)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, 3)
                .background(theme.bgPrimary.color)
                .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                        .strokeBorder(scopeBorderColor, lineWidth: 1)
                )
        } else {
            Text(scopeBadge)
                .brevFont(.caption)
                .foregroundStyle(scopeForegroundColor)
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, 3)
                .background(theme.bgPrimary.color)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(scopeBorderColor, lineWidth: 1)
                )
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var scopeForegroundColor: Color {
        switch scopeTone {
        case .onDevice:
            theme.success.color
        case .mailServer, .network:
            theme.textSecondary.color
        }
    }

    private var scopeBorderColor: Color {
        switch scopeTone {
        case .onDevice:
            theme.success.color.opacity(0.45)
        case .mailServer, .network:
            theme.border.color
        }
    }
}

private struct PrivacyOnboardingToggleRow: View {
    @Environment(\.brevTheme) private var theme
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title)
                    .brevFont(.body)
                    .foregroundStyle(
                        (isEnabled ? theme.textPrimary : theme.textSecondary).color
                    )
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, BrevSpacing.sm)
        }
        .toggleStyle(.switch)
        .tint(theme.accent.color)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
