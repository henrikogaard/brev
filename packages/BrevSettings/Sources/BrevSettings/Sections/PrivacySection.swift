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

struct PrivacySection: View {
    @Environment(\.brevTheme) private var theme
    @State private var avatarSettings: AvatarPrivacySettings
    @State private var browserSettings: BrowserSettings
    @State private var mailboxSettings: MailboxViewSettings
    @State private var remoteContentPolicy: RemoteContentPolicy
    @State private var preferenceSyncSettings: PreferenceSyncSettings

    private let settingsStore: SettingsPersistenceStore

    init(settingsStore: SettingsPersistenceStore = .standard) {
        self.settingsStore = settingsStore
        _avatarSettings = State(initialValue: settingsStore.avatarPrivacySettings())
        _browserSettings = State(initialValue: settingsStore.browserSettings())
        _mailboxSettings = State(initialValue: settingsStore.mailboxViewSettings())
        _remoteContentPolicy = State(initialValue: settingsStore.remoteContentPolicy())
        _preferenceSyncSettings = State(initialValue: settingsStore.preferenceSyncSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Privacy", bundle: .module),
            subtitle: String(localized: "A quick view of Brev's network and data boundaries.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                privacyDefaults
                browserGroup
                optInStatus
                preferenceSyncGroup
                remoteContentAllowlist
            }
            .onAppear {
                avatarSettings = settingsStore.avatarPrivacySettings()
                browserSettings = settingsStore.browserSettings()
                mailboxSettings = settingsStore.mailboxViewSettings()
                remoteContentPolicy = settingsStore.remoteContentPolicy()
                preferenceSyncSettings = settingsStore.preferenceSyncSettings()
            }
        }
    }

    private var privacyDefaults: some View {
        SettingsGroup(
            title: String(localized: "Defaults", bundle: .module),
            subtitle: String(localized: "Brev starts with conservative mail-rendering choices.", bundle: .module),
            symbolName: "lock.shield"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                privacyRow(
                    symbolName: "eye.slash",
                    title: String(localized: "Remote content starts blocked", bundle: .module),
                    subtitle: String(
                        localized: "Images, web fonts, and tracking pixels remain off unless enabled in Mailbox View.",
                        bundle: .module
                    )
                )
                privacyRow(
                    symbolName: "person.crop.circle",
                    title: String(localized: "Sender icons are explicit", bundle: .module),
                    subtitle: String(
                        localized: "Contacts stay local; Gravatar, BIMI, and favicons are controlled from Mailbox View.",
                        bundle: .module
                    )
                )
                privacyRow(
                    symbolName: "wand.and.stars",
                    title: String(localized: "AI Writer requires consent", bundle: .module),
                    subtitle: String(
                        localized: "Draft text is only sent when you enable AI Writer and choose an AI action.",
                        bundle: .module
                    )
                )
            }
        }
    }

    private var browserGroup: some View {
        SettingsGroup(
            title: String(localized: "Browser", bundle: .module),
            subtitle: String(localized: "Choose where Brev opens links from messages and settings.", bundle: .module),
            symbolName: "safari"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsPickerRow(
                    symbolName: "link",
                    title: String(localized: "Open links in", bundle: .module),
                    subtitle: browserSettings.preferredBrowser.subtitle,
                    selection: browserBinding(for: \.preferredBrowser)
                ) {
                    ForEach(BrowserChoice.availableChoices) { browser in
                        Text(browser.title).tag(browser)
                    }
                }

                SettingsInfoCallout(
                    symbolName: "arrow.up.right.square",
                    message: browserOpeningMessage,
                    tone: .info
                )
            }
        }
    }

    private var remoteContentAllowlist: some View {
        SettingsGroup(
            title: String(localized: "Remote content allowlist", bundle: .module),
            subtitle: String(localized: "Review senders and domains allowed to load remote images.", bundle: .module),
            symbolName: "photo.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if remoteContentPolicy.hasAllowlistEntries {
                    ForEach(remoteContentPolicy.allowedSenderEntries, id: \.self) { sender in
                        allowlistRow(
                            symbolName: "person.crop.circle",
                            title: sender,
                            subtitle: String(localized: "Sender", bundle: .module),
                            onRevoke: { revokeSender(sender) }
                        )
                    }

                    ForEach(remoteContentPolicy.allowedDomainEntries, id: \.self) { domain in
                        allowlistRow(
                            symbolName: "globe",
                            title: domain,
                            subtitle: String(localized: "Domain", bundle: .module),
                            onRevoke: { revokeDomain(domain) }
                        )
                    }
                } else {
                    SettingsInfoCallout(
                        symbolName: "checkmark.shield",
                        message: String(
                            localized: "No senders or domains are allowed to load remote content automatically.",
                            bundle: .module
                        ),
                        tone: .success
                    )
                }
            }
        }
    }

    private var optInStatus: some View {
        SettingsGroup(
            title: String(localized: "Current opt-ins", bundle: .module),
            subtitle: String(localized: "Status pulled from your saved settings.", bundle: .module),
            symbolName: "checklist"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsInfoCallout(
                    symbolName: mailboxSettings.allowRemoteContent ? "network" : "checkmark.shield",
                    message: remoteContentStatus,
                    tone: mailboxSettings.allowRemoteContent ? .warning : .success
                )
                SettingsInfoCallout(
                    symbolName: avatarSettings.usesExternalSources ? "network" : "checkmark.shield",
                    message: avatarStatus,
                    tone: avatarSettings.usesExternalSources ? .warning : .success
                )
            }
        }
    }

    private var preferenceSyncGroup: some View {
        SettingsGroup(
            title: String(localized: "iCloud sync", bundle: .module),
            subtitle: String(
                localized: "Mirror a small set of preferences between your devices through your own iCloud account.",
                bundle: .module
            ),
            symbolName: "icloud"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "arrow.triangle.2.circlepath.icloud",
                    title: String(localized: "Sync preferences with iCloud", bundle: .module),
                    subtitle: String(
                        localized: "Snoozes, VIPs, inbox category choices, pinned messages, blocked senders, reminders, signatures, templates, smart mailboxes, compose, and sidebar preferences. Never mail, accounts, or passwords.",
                        bundle: .module
                    ),
                    isOn: preferenceSyncBinding
                )
                SettingsInfoCallout(
                    symbolName: preferenceSyncSettings.isICloudSyncEnabled ? "icloud.fill" : "icloud.slash",
                    message: preferenceSyncStatus,
                    tone: preferenceSyncSettings.isICloudSyncEnabled ? .info : .success
                )
            }
        }
    }

    private var preferenceSyncStatus: String {
        if preferenceSyncSettings.isICloudSyncEnabled {
            return "Preferences are stored in Apple iCloud Key-Value Storage under your Apple ID and may take a moment to reach other devices. Turning this off stops syncing on this device only."
        }
        return String(localized: "Preferences stay on this device.", bundle: .module)
    }

    private var preferenceSyncBinding: Binding<Bool> {
        Binding(
            get: { preferenceSyncSettings.isICloudSyncEnabled },
            set: { newValue in
                preferenceSyncSettings.isICloudSyncEnabled = newValue
                settingsStore.save(preferenceSyncSettings)
            }
        )
    }

    private var remoteContentStatus: String {
        if mailboxSettings.useRichRenderer, mailboxSettings.allowRemoteContent {
            return String(localized: "Remote images are allowed by default for rich HTML messages.", bundle: .module)
        }
        return String(localized: "Remote images are not loaded by default.", bundle: .module)
    }

    private var avatarStatus: String {
        if avatarSettings.usesExternalSources {
            return String(localized: "At least one external sender icon source is enabled.", bundle: .module)
        }
        if avatarSettings.useContacts {
            return String(localized: "Sender icons use local Contacts photos and generated initials.", bundle: .module)
        }
        return String(localized: "Sender icons use generated initials only.", bundle: .module)
    }

    private var browserOpeningMessage: String {
        switch browserSettings.preferredBrowser {
        case .systemDefault:
            return String(localized: "Brev asks the operating system to open links in your default browser.", bundle: .module)
        case .safari:
            return String(localized: "Brev targets Safari directly on macOS.", bundle: .module)
        default:
            return String(
                localized: "Brev will try to open links in the selected browser and fall back if it is unavailable.",
                bundle: .module
            )
        }
    }

    private func privacyRow(
        symbolName: String,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(theme.accent.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(subtitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func allowlistRow(
        symbolName: String,
        title: String,
        subtitle: String,
        onRevoke: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: BrevSpacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(theme.accent.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            Spacer(minLength: BrevSpacing.md)
            Button(action: onRevoke) {
                Image(systemName: "trash")
                    .foregroundStyle(theme.danger.color)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Remove allowlist entry", bundle: .module))
        }
    }

    private func revokeSender(_ sender: String) {
        remoteContentPolicy.revoke(senderEmail: sender)
        settingsStore.save(remoteContentPolicy)
    }

    private func revokeDomain(_ domain: String) {
        remoteContentPolicy.revoke(domain: domain)
        settingsStore.save(remoteContentPolicy)
    }

    private func browserBinding<Value>(
        for keyPath: WritableKeyPath<BrowserSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { browserSettings[keyPath: keyPath] },
            set: { newValue in
                browserSettings[keyPath: keyPath] = newValue
                settingsStore.save(browserSettings)
            }
        )
    }
}
