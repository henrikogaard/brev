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
import Foundation
import SwiftUI

/// Settings group controlling opt-in background recent-mail and attachment indexing.
///
/// Strictly off by default; expands with window, attachment, power/network, and
/// live progress/action controls once enabled.
struct BackgroundIndexingSettingsGroup: View {
    private let settingsStore: SettingsPersistenceStore
    private let statusModel: BackgroundIndexingStatusModel?
    private let referenceDate: Date

    @State private var settings: BackgroundIndexingSettings
    @State private var isResettingState = false

    init(
        settingsStore: SettingsPersistenceStore,
        statusModel: BackgroundIndexingStatusModel? = nil,
        referenceDate: Date = Date()
    ) {
        self.settingsStore = settingsStore
        self.statusModel = statusModel
        self.referenceDate = referenceDate
        _settings = State(initialValue: settingsStore.backgroundIndexingSettings())
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "Background indexing", bundle: .module),
            subtitle: String(
                localized: "Pre-fetch recent mail locally so offline and attachment search respond immediately.",
                bundle: .module
            ),
            symbolName: "arrow.down.doc"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "arrow.down.doc",
                    title: String(localized: "Index recent mail & attachments in background", bundle: .module),
                    subtitle: String(
                        localized: "Downloads recent message bodies and eligible attachment text locally for instant offline search. Off by default.",
                        bundle: .module
                    ),
                    isOn: enabledBinding
                )

                if settings.isEnabled {
                    SettingsPickerRow(
                        symbolName: "calendar",
                        title: String(localized: "Indexing window", bundle: .module),
                        subtitle: String(
                            localized: "Only messages received inside this window are fetched automatically. Trash and Spam are skipped.",
                            bundle: .module
                        ),
                        selection: windowBinding,
                        selectionTitle: settings.windowDays.displayName
                    ) {
                        ForEach(BackgroundIndexingWindow.allCases) { window in
                            Text(window.displayName).tag(window)
                        }
                    }

                    SettingsToggleRow(
                        symbolName: "paperclip",
                        title: String(localized: "Index attachment text", bundle: .module),
                        subtitle: String(
                            localized: "Downloads eligible PDF, text, RTF, and HTML attachments up to 10 MB for local full-text search.",
                            bundle: .module
                        ),
                        isOn: indexAttachmentsBinding
                    )

                    SettingsToggleRow(
                        symbolName: "wifi",
                        title: String(localized: "Wi-Fi & power friendly", bundle: .module),
                        subtitle: String(
                            localized: "Pause automatically on cellular, Low Data Mode, or Low Power Mode.",
                            bundle: .module
                        ),
                        isOn: requireUnmeteredBinding
                    )

                    SettingsInfoCallout(
                        symbolName: BackgroundIndexingStatusPresentation.symbolName(
                            settings: settings,
                            status: currentStatus
                        ),
                        message: BackgroundIndexingStatusPresentation.summary(
                            settings: settings,
                            status: currentStatus,
                            now: referenceDate
                        ),
                        tone: BackgroundIndexingStatusPresentation.tone(
                            settings: settings,
                            status: currentStatus
                        )
                    )

                    if let statusModel {
                        actionButtons(for: statusModel)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brevBackgroundIndexingSettingsDidChange)) { _ in
            settings = settingsStore.backgroundIndexingSettings()
        }
    }

    private var currentStatus: BackgroundIndexingStatus {
        statusModel?.status ?? .idle
    }

    @ViewBuilder
    private func actionButtons(for model: BackgroundIndexingStatusModel) -> some View {
        SettingsButtonRow {
            if BackgroundIndexingStatusPresentation.isRunning(currentStatus.state) {
                SettingsButton(String(localized: "Pause", bundle: .module), style: .secondary) {
                    model.onPause?()
                }
            } else if BackgroundIndexingStatusPresentation.isUserPaused(currentStatus.state) {
                SettingsButton(String(localized: "Resume", bundle: .module), style: .primary) {
                    model.onResume?()
                }
            } else {
                SettingsButton(String(localized: "Index now", bundle: .module), style: .secondary) {
                    Task { await model.onIndexNow?() }
                }
            }

            SettingsButton(String(localized: "Reset index state", bundle: .module), style: .secondary) {
                guard !isResettingState else { return }
                isResettingState = true
                Task {
                    defer { isResettingState = false }
                    await model.onResetIndexState?()
                }
            }
            .disabled(isResettingState)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                settings.isEnabled = newValue
                persistSettings()
            }
        )
    }

    private var windowBinding: Binding<BackgroundIndexingWindow> {
        Binding(
            get: { settings.windowDays },
            set: { newValue in
                settings.windowDays = newValue
                persistSettings()
            }
        )
    }

    private var indexAttachmentsBinding: Binding<Bool> {
        Binding(
            get: { settings.indexAttachments },
            set: { newValue in
                settings.indexAttachments = newValue
                persistSettings()
            }
        )
    }

    private var requireUnmeteredBinding: Binding<Bool> {
        Binding(
            get: { settings.requireUnmeteredNetworkAndPower },
            set: { newValue in
                settings.requireUnmeteredNetworkAndPower = newValue
                persistSettings()
            }
        )
    }

    private func persistSettings() {
        settingsStore.save(settings)
        if settingsStore.defaults !== UserDefaults.standard {
            NotificationCenter.default.post(name: .brevBackgroundIndexingSettingsDidChange, object: nil)
        }
    }
}
