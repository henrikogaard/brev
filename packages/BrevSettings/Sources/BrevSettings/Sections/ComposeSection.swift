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

#if canImport(Contacts)
import Contacts
#endif

struct ComposeSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var settings: ComposeSettings
    @State private var recipientSuggestionSettings: RecipientSuggestionSettings
    @State private var recentRecipients: [RecentRecipient]

    private let settingsStore: SettingsPersistenceStore
    private let recentRecipientStore: RecentRecipientStore

    init(settingsStore: SettingsPersistenceStore = .standard) {
        self.settingsStore = settingsStore
        let recentRecipientStore = RecentRecipientStore(defaults: settingsStore.defaults)
        self.recentRecipientStore = recentRecipientStore
        _settings = State(initialValue: settingsStore.composeSettings())
        _recipientSuggestionSettings = State(initialValue: RecipientSuggestionSettings.load(from: settingsStore.defaults))
        _recentRecipients = State(initialValue: recentRecipientStore.allRecipients())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Compose", bundle: .module),
            subtitle: String(localized: "Local defaults for replies, forwarding, formatting, and send safety.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                defaultsGroup
                recipientSuggestionsGroup
                safetyGroup
            }
            .onAppear { refreshRecentRecipients() }
        }
    }

    private var defaultsGroup: some View {
        SettingsGroup(
            title: String(localized: "Defaults", bundle: .module),
            subtitle: String(localized: "Choose the behavior Brev should preselect in the composer.", bundle: .module),
            symbolName: "square.and.pencil"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsPickerRow(
                    symbolName: "textformat",
                    title: String(localized: "Message format", bundle: .module),
                    subtitle: String(
                        localized: "Automatic uses rich text while Plain Text keeps outgoing markup escaped.",
                        bundle: .module
                    ),
                    selection: binding(for: \.messageFormat)
                ) {
                    ForEach(ComposeMessageFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }

                SettingsPickerRow(
                    symbolName: "quote.bubble",
                    title: String(localized: "Quoted text", bundle: .module),
                    subtitle: String(localized: "Choose where original message text appears in replies.", bundle: .module),
                    selection: binding(for: \.quotePlacement)
                ) {
                    ForEach(ComposeQuotePlacement.allCases, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }

                SettingsToggleRow(
                    symbolName: "textformat.abc",
                    title: String(localized: "Check spelling while typing", bundle: .module),
                    subtitle: String(
                        localized: "Use the system spell-check, grammar, and autocorrect helpers in the compose body.",
                        bundle: .module
                    ),
                    isOn: binding(for: \.textCheckingEnabled)
                )
            }
        }
    }

    private var safetyGroup: some View {
        SettingsGroup(
            title: String(localized: "Send safety", bundle: .module),
            subtitle: String(localized: "Keep small guardrails active while composing mail.", bundle: .module),
            symbolName: "checkmark.shield"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "paperclip.badge.ellipsis",
                    title: String(localized: "Attachment reminder", bundle: .module),
                    subtitle: String(
                        localized: "Warn before sending when the draft mentions attachments but none are added.",
                        bundle: .module
                    ),
                    isOn: binding(for: \.attachmentReminderEnabled)
                )

                SettingsToggleRow(
                    symbolName: "person.crop.circle.badge.exclamationmark",
                    title: String(localized: "External recipient warning", bundle: .module),
                    subtitle: String(
                        localized: "Warn before sending to recipients outside the current account domain.",
                        bundle: .module
                    ),
                    isOn: binding(for: \.externalRecipientWarningEnabled)
                )

                SettingsPickerRow(
                    symbolName: "clock.arrow.circlepath",
                    title: String(localized: "Undo send delay", bundle: .module),
                    subtitle: String(
                        localized: "Keeps outgoing messages locally queued before handoff to the backend.",
                        bundle: .module
                    ),
                    selection: binding(for: \.undoSendDelay)
                ) {
                    ForEach(ComposeUndoSendDelay.allCases, id: \.self) { delay in
                        Text(delay.title).tag(delay)
                    }
                }

                SettingsInfoCallout(
                    symbolName: "tray",
                    message: String(
                        localized: "When enabled, Send holds the draft locally for the selected delay so you can cancel before backend handoff.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    private var recipientSuggestionsGroup: some View {
        SettingsGroup(
            title: String(localized: "Recipient suggestions", bundle: .module),
            subtitle: String(
                localized: "Use device contacts and Brev's separate local correspondence list while addressing mail.",
                bundle: .module
            ),
            symbolName: "person.crop.circle.badge.plus"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "person.crop.circle",
                    title: String(localized: "Use Contacts app", bundle: .module),
                    subtitle: String(
                        localized: "Shows matching Apple Contacts in the composer. Brev never adds or edits Apple Contacts.",
                        bundle: .module
                    ),
                    isOn: Binding(
                        get: { recipientSuggestionSettings.useAppleContacts },
                        set: { isEnabled in
                            recipientSuggestionSettings.useAppleContacts = isEnabled
                            recipientSuggestionSettings.save(to: settingsStore.defaults)
                            if isEnabled {
                                requestContactsAccessFromExplicitSettingsAction()
                            }
                        }
                    )
                )

                if recentRecipients.isEmpty {
                    Text("No recent recipients yet.", bundle: .module)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(recentRecipients) { recipient in
                            recentRecipientRow(recipient)
                        }
                    }

                    Button(String(localized: "Clear recent recipients", bundle: .module), role: .destructive) {
                        recentRecipientStore.removeAll()
                        refreshRecentRecipients()
                    }
                    .buttonStyle(.borderless)
                }

                SettingsInfoCallout(
                    symbolName: "hand.raised",
                    message: String(
                        localized: "Recent recipients are stored only in Brev on this device. Removing one never changes the Contacts app.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    private func requestContactsAccessFromExplicitSettingsAction() {
        #if canImport(Contacts)
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { return }
        Task {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        }
        #endif
    }

    private func recentRecipientRow(_ recipient: RecentRecipient) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(recipient.displayName ?? recipient.email)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                if recipient.displayName != nil {
                    Text(recipient.email)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: BrevSpacing.sm)
            Button {
                recentRecipientStore.remove(email: recipient.email)
                refreshRecentRecipients()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(theme.danger.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove \(recipient.email) from recent recipients", bundle: .module))
            .help(String(localized: "Remove from recent recipients", bundle: .module))
        }
        .padding(.vertical, BrevSpacing.xs)
    }

    private func binding<Value>(
        for keyPath: WritableKeyPath<ComposeSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                settingsStore.save(settings)
            }
        )
    }

    private func refreshRecentRecipients() {
        recentRecipients = recentRecipientStore.allRecipients()
    }
}
