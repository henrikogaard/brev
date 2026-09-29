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

struct PreferenceSyncSection: View {
    @State private var preferenceSyncSettings: PreferenceSyncSettings
    private let settingsStore: SettingsPersistenceStore

    init(settingsStore: SettingsPersistenceStore) {
        self.settingsStore = settingsStore
        _preferenceSyncSettings = State(initialValue: settingsStore.preferenceSyncSettings())
    }

    var body: some View {
        SectionScaffold(title: String(localized: "Preferences", bundle: .module)) {
            preferenceSyncGroup
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
            return String(
                localized: "Preferences are stored in Apple iCloud Key-Value Storage under your Apple ID and may take a moment to reach other devices. Turning this off stops syncing on this device only.",
                bundle: .module
            )
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
}
