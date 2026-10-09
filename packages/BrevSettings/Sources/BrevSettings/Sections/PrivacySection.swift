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

import BrevAvatars
import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

#if canImport(Contacts)
import Contacts
#endif

struct PrivacySection: View {
    @Environment(\.brevTheme) private var theme
    @State private var avatarSettings: AvatarPrivacySettings
    @State private var mailboxSettings: MailboxViewSettings
    @State private var remoteContentPolicy: RemoteContentPolicy
    #if os(iOS)
    /// The allowlist entry the user asked to remove, awaiting confirmation.
    @State private var pendingRevocation: PendingAllowlistRevocation?
    #endif

    private let settingsStore: SettingsPersistenceStore

    init(settingsStore: SettingsPersistenceStore = .standard) {
        self.settingsStore = settingsStore
        _avatarSettings = State(initialValue: settingsStore.avatarPrivacySettings())
        _mailboxSettings = State(initialValue: settingsStore.mailboxViewSettings())
        _remoteContentPolicy = State(initialValue: settingsStore.remoteContentPolicy())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Privacy", bundle: .module),
            subtitle: String(localized: "Control remote images, sender image sources, and trusted senders.", bundle: .module)
        ) {
            SettingsGroupStack {
                remoteImagesGroup
                senderIconGroup
                remoteContentAllowlist
                privacyDefaults
            }
            .onAppear {
                avatarSettings = settingsStore.avatarPrivacySettings()
                mailboxSettings = settingsStore.mailboxViewSettings()
                remoteContentPolicy = settingsStore.remoteContentPolicy()
            }
        }
        #if os(iOS)
        .confirmationDialog(
            String(localized: "Remove this allowlist entry?", bundle: .module),
            isPresented: Binding(
                get: { pendingRevocation != nil },
                set: { if !$0 { pendingRevocation = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRevocation
        ) { pending in
            Button(String(localized: "Remove \(pending.title)", bundle: .module), role: .destructive) {
                pending.revoke()
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: { _ in
            Text("Remote content from this sender is blocked again.", bundle: .module)
        }
        #endif
    }

    private var privacyDefaults: some View {
        SettingsGroup(
            title: String(localized: "Defaults", bundle: .module),
            subtitle: String(localized: "Brev starts with conservative mail-rendering choices.", bundle: .module),
            symbolName: "lock.shield"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                privacyRow(
                    symbolName: "eye.slash",
                    title: String(localized: "Remote content starts blocked", bundle: .module),
                    subtitle: String(
                        localized: "Images, web fonts, and tracking pixels remain off unless you allow remote content.",
                        bundle: .module
                    )
                )
                privacyRow(
                    symbolName: "person.crop.circle",
                    title: String(localized: "Sender icons are explicit", bundle: .module),
                    subtitle: String(
                        localized: "Contacts stay local; external sender image sources require your permission above.",
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

    private var remoteContentAllowlist: some View {
        SettingsGroup(
            title: String(localized: "Remote content allowlist", bundle: .module),
            subtitle: String(localized: "Review senders and domains allowed to load remote images.", bundle: .module),
            symbolName: "photo.badge.checkmark"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
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

    private var remoteContentStatus: String {
        if mailboxSettings.useRichRenderer, mailboxSettings.allowRemoteContent {
            return String(localized: "Remote images are allowed by default for rich HTML messages.", bundle: .module)
        }
        return String(localized: "Remote images are not loaded by default.", bundle: .module)
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
            Button {
                #if os(iOS)
                pendingRevocation = PendingAllowlistRevocation(title: title, revoke: onRevoke)
                #else
                onRevoke()
                #endif
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(theme.danger.color)
                #if os(iOS)
                    .frame(minWidth: 44, minHeight: 44)
                #endif
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove allowlist entry", bundle: .module))
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

    private var remoteImagesGroup: some View {
        SettingsGroup(title: String(localized: "Remote content", bundle: .module),
                      subtitle: String(
                          localized: "Images, web fonts, and tracking pixels are blocked until you allow them.",
                          bundle: .module
                      ),
                      symbolName: "photo") {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "photo",
                    title: String(localized: "Always load remote images", bundle: .module),
                    subtitle: String(localized: "Allows remote images after rich HTML rendering is enabled.", bundle: .module),
                    isOn: mailboxBinding(for: \.allowRemoteContent),
                    isEnabled: mailboxSettings.useRichRenderer
                )

                SettingsInfoCallout(symbolName: "checkmark.shield", message: remoteContentStatus, tone: .info)
            }
        }
    }

    private var senderIconGroup: some View {
        SettingsGroup(
            title: String(localized: "Sender image sources", bundle: .module),
            subtitle: String(
                localized: "Choose which avatar sources Brev may use when sender images are visible.",
                bundle: .module
            ),
            symbolName: "person.crop.circle.badge.checkmark"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "person.crop.square",
                    title: String(localized: "Use Contacts photos", bundle: .module),
                    subtitle: String(localized: "Looks up sender photos locally on this device.", bundle: .module),
                    isOn: avatarBinding(for: \.useContacts),
                    isEnabled: mailboxSettings.showSenderAvatars
                )

                SettingsToggleRow(
                    symbolName: "number.circle",
                    title: String(localized: "Use Gravatar", bundle: .module),
                    subtitle: String(localized: "Sends a SHA-256 hash of the sender address to gravatar.com.", bundle: .module),
                    isOn: avatarBinding(for: \.useGravatar),
                    isEnabled: mailboxSettings.showSenderAvatars
                )

                SettingsToggleRow(
                    symbolName: "checkmark.seal",
                    title: String(localized: "Use BIMI logos", bundle: .module),
                    subtitle: String(localized: "Allows DNS lookups for sender-domain BIMI records.", bundle: .module),
                    isOn: avatarBinding(for: \.useBIMI),
                    isEnabled: mailboxSettings.showSenderAvatars
                )

                SettingsToggleRow(
                    symbolName: "globe",
                    title: String(localized: "Use domain favicons", bundle: .module),
                    subtitle: String(localized: "Allows fetching icons from sender domains during sync.", bundle: .module),
                    isOn: avatarBinding(for: \.useFavicon),
                    isEnabled: mailboxSettings.showSenderAvatars
                )

                SettingsButtonRow {
                    SettingsButton(String(localized: "Initials only", bundle: .module), style: .secondary) {
                        updateAvatarSettings { $0.useInitialsOnly() }
                    }
                    SettingsButton(String(localized: "Clear cached avatars", bundle: .module), style: .tertiary) {
                        Task { await AvatarResolver.shared.clearCache() }
                    }
                    Spacer(minLength: BrevSpacing.md)
                }
                .disabled(!mailboxSettings.showSenderAvatars)
                .opacity(mailboxSettings.showSenderAvatars ? 1 : 0.55)

                SettingsInfoCallout(
                    symbolName: avatarFooterSymbolName,
                    message: avatarFooterText,
                    tone: avatarFooterTone
                )
            }
        }
    }

    private var avatarFooterText: String {
        if !mailboxSettings.showSenderAvatars {
            return String(
                localized: "Sender images are hidden, so mailbox rows and message headers stay more compact.",
                bundle: .module
            )
        }
        if avatarSettings.usesExternalSources {
            return String(localized: "External sender icon lookups are enabled for at least one source.", bundle: .module)
        }
        if avatarSettings.useContacts {
            return String(
                localized: "External sender icon lookups are off. Brev uses Contacts photos and generated initials.",
                bundle: .module
            )
        }
        return String(localized: "All sender icon sources are off. Brev uses generated initials only.", bundle: .module)
    }

    private var avatarFooterSymbolName: String {
        if !mailboxSettings.showSenderAvatars {
            return "eye.slash"
        }
        if avatarSettings.usesExternalSources {
            return "network"
        }
        if avatarSettings.useContacts {
            return "checkmark.shield"
        }
        return "person.crop.circle"
    }

    private var avatarFooterTone: SettingsCalloutTone {
        if !mailboxSettings.showSenderAvatars {
            return .info
        }
        if avatarSettings.usesExternalSources {
            return .warning
        }
        if avatarSettings.useContacts {
            return .success
        }
        return .info
    }

    private func avatarBinding(
        for keyPath: WritableKeyPath<AvatarPrivacySettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { avatarSettings[keyPath: keyPath] },
            set: { newValue in
                updateAvatarSettings { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func updateAvatarSettings(
        _ mutate: (inout AvatarPrivacySettings) -> Void
    ) {
        let previouslyUsedContacts = avatarSettings.useContacts
        mutate(&avatarSettings)
        settingsStore.save(avatarSettings)
        if !previouslyUsedContacts, avatarSettings.useContacts {
            requestContactsAccessFromExplicitSettingsAction()
        }
        let preferences = avatarSettings.avatarPreferences
        Task {
            await AvatarResolver.shared.updatePreferences(preferences)
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

    private func mailboxBinding<Value>(
        for keyPath: WritableKeyPath<MailboxViewSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { mailboxSettings[keyPath: keyPath] },
            set: { newValue in
                mailboxSettings[keyPath: keyPath] = newValue
                settingsStore.save(mailboxSettings)
            }
        )
    }
}

#if os(iOS)
/// An allowlist removal waiting for the user's confirmation.
private struct PendingAllowlistRevocation {
    let title: String
    let revoke: () -> Void
}
#endif
