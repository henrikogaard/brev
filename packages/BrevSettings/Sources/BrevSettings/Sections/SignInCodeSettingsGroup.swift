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
import SwiftUI

/// Per-account consent for the sign-in panel (ADR-0088 decision 11).
///
/// Both opt-ins default off and are stored only in the given local
/// defaults — never in backup or iCloud sync. Accounts whose backend does
/// not advertise a trusted sign-in assessment show why they cannot be
/// enabled instead of a switch that silently does nothing.
struct SignInCodeSettingsGroup: View {
    @Environment(\.brevTheme) private var theme

    let accounts: [BrevAccount]
    /// Whether the account's backend advertises
    /// `.trustedSignInAssessment`.
    let isAvailable: (BrevAccount.ID) -> Bool
    /// Called after a consent change so the arrival controller can cancel
    /// pending work for the account.
    var onChange: (BrevAccount.ID) -> Void = { _ in }
    @State private var settings: SignInCodeSettings
    private let defaults: UserDefaults

    init(
        accounts: [BrevAccount],
        settingsStore: SettingsPersistenceStore,
        isAvailable: @escaping (BrevAccount.ID) -> Bool,
        onChange: @escaping (BrevAccount.ID) -> Void = { _ in }
    ) {
        self.accounts = accounts
        self.isAvailable = isAvailable
        self.onChange = onChange
        defaults = settingsStore.defaults
        _settings = State(initialValue: SignInCodeSettings.load(from: settingsStore.defaults))
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "Sign-in codes and links", bundle: .module),
            subtitle: String(
                localized: "Shows a one-time code or sign-in link on screen the moment it arrives. For eligible new messages Brev reads the message body over the account's own connection, and codes may appear over other apps. Nothing is stored, logged, or synced.",
                bundle: .module
            ),
            symbolName: "key.viewfinder"
        ) {
            SettingsRowStack {
                if accounts.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "person.crop.circle.badge.questionmark",
                        message: String(localized: "Connect an account to turn this on per mailbox.", bundle: .module),
                        tone: .info
                    )
                } else {
                    ForEach(accounts) { account in
                        accountCard(account)
                    }
                }
            }
        }
    }

    private func accountCard(_ account: BrevAccount) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName.isEmpty ? account.emailAddress : account.displayName)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Text(account.emailAddress)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            if isAvailable(account.id) {
                SettingsToggleRow(
                    symbolName: "number",
                    title: String(localized: "Show one-time codes", bundle: .module),
                    subtitle: String(localized: "Copy a sign-in code without opening the message.", bundle: .module),
                    isOn: binding(account.id, codes: true)
                )
                SettingsToggleRow(
                    symbolName: "link",
                    title: String(localized: "Show sign-in links", bundle: .module),
                    subtitle: String(localized: "Open a sign-in link after seeing its real destination.", bundle: .module),
                    isOn: binding(account.id, codes: false)
                )
            } else {
                SettingsInfoCallout(
                    symbolName: "lock.shield",
                    message: String(
                        localized: "Not available for this account yet. Brev only enables this where the provider's sender checks have been verified.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
        .padding(BrevSpacing.md)
        .settingsInlineSurface()
    }

    private func binding(_ accountID: BrevAccount.ID, codes: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let override = settings.accountOverride(for: accountID)
                return codes ? override.codesEnabled : override.linksEnabled
            },
            set: { isOn in
                let current = settings.accountOverride(for: accountID)
                settings.setAccountOverride(
                    accountID: accountID,
                    codesEnabled: codes ? isOn : current.codesEnabled,
                    linksEnabled: codes ? current.linksEnabled : isOn
                )
                settings.save(to: defaults)
                onChange(accountID)
            }
        )
    }
}
