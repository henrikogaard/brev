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

struct BrowserSettingsGroup: View {
    @State private var browserSettings: BrowserSettings
    private let settingsStore: SettingsPersistenceStore

    init(settingsStore: SettingsPersistenceStore) {
        self.settingsStore = settingsStore
        _browserSettings = State(initialValue: settingsStore.browserSettings())
    }

    var body: some View { browserGroup }

    private var browserGroup: some View {
        SettingsGroup(
            title: String(localized: "Browser", bundle: .module),
            subtitle: String(localized: "Choose where Brev opens links from messages and settings.", bundle: .module),
            symbolName: "safari"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
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
