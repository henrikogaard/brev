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
import SwiftUI

struct DeveloperSection: View {
    private let settingsStore: SettingsPersistenceStore
    private let actions: DeveloperSettingsActions
    @State private var settings: DeveloperSettings

    init(
        settingsStore: SettingsPersistenceStore,
        actions: DeveloperSettingsActions
    ) {
        self.settingsStore = settingsStore
        self.actions = actions
        _settings = State(initialValue: settingsStore.developerSettings())
    }

    var body: some View {
        SectionScaffold(title: String(localized: "Developer", bundle: .module)) {
            SettingsGroup(
                title: String(localized: "Runtime", bundle: .module),
                subtitle: String(localized: "Debug-build controls for local development.", bundle: .module),
                symbolName: "hammer"
            ) {
                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    SettingsToggleRow(
                        symbolName: "shippingbox",
                        title: String(localized: "Demo mailbox mode", bundle: .module),
                        subtitle: String(
                            localized: "Restart Brev with the local demo mailbox instead of restored accounts.",
                            bundle: .module
                        ),
                        isOn: demoModeBinding
                    )

                    SettingsInfoCallout(
                        symbolName: "arrow.clockwise",
                        message: String(
                            localized: "Changing this setting relaunches Brev so startup uses the selected runtime.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                }
            }
        }
    }

    private var demoModeBinding: Binding<Bool> {
        Binding(
            get: { settings.demoModeEnabled },
            set: { isEnabled in
                guard settings.demoModeEnabled != isEnabled else { return }
                settings.demoModeEnabled = isEnabled
                settingsStore.save(settings)
                Task { @MainActor in
                    await actions.applyDemoMode(isEnabled)
                }
            }
        )
    }
}
