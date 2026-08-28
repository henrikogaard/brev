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

import BrevSettings
import Foundation
import Sparkle

@MainActor
final class MacUpdateController: NSObject, SPUUpdaterDelegate {
    private let settingsStore: SettingsPersistenceStore
    private let buildConfiguration: UpdateBuildConfiguration
    private var updaterController: SPUStandardUpdaterController?
    private var currentSettings = UpdateSettings.defaults
    private var lastAppliedSettings: UpdateSettings?
    private var didStartUpdater = false
    private var didRunLaunchCheck = false

    init(
        bundle: Bundle = .main,
        settingsStore: SettingsPersistenceStore = .standard
    ) {
        self.settingsStore = settingsStore
        buildConfiguration = UpdateBuildConfiguration(
            infoDictionary: bundle.infoDictionary ?? [:],
            platform: .macOS
        )
        super.init()
    }

    var settingsActions: SettingsUpdateActions {
        SettingsUpdateActions(
            isManualCheckAvailable: buildConfiguration.canInitializeSparkle,
            checkForUpdates: { [weak self] in
                self?.checkForUpdates()
            },
            settingsDidChange: { [weak self] settings in
                self?.apply(settings)
            }
        )
    }

    func startIfConfigured() {
        let settings = settingsStore.updateSettings()
        guard buildConfiguration.canInitializeSparkle else { return }

        currentSettings = settings
        guard settings.startsUpdaterOnLaunch else { return }

        ensureUpdaterController()
        apply(settings)

        guard let updaterController else { return }
        startUpdaterIfNeeded()

        if settings.cadence == .oncePerLaunch, !didRunLaunchCheck {
            updaterController.updater.checkForUpdatesInBackground()
            didRunLaunchCheck = true
        }
    }

    private func checkForUpdates() {
        guard buildConfiguration.canInitializeSparkle else { return }
        ensureUpdaterController()
        apply(settingsStore.updateSettings())
        startUpdaterIfNeeded()
        updaterController?.checkForUpdates(nil)
    }

    private func apply(_ settings: UpdateSettings) {
        currentSettings = settings
        guard buildConfiguration.canInitializeSparkle else { return }
        ensureUpdaterController()
        guard lastAppliedSettings != settings else { return }
        guard let updater = updaterController?.updater else { return }

        updater.automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
        updater.updateCheckInterval = settings.scheduledCheckInterval
        lastAppliedSettings = settings
    }

    private func ensureUpdaterController() {
        guard updaterController == nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    private func startUpdaterIfNeeded() {
        guard let updaterController, !didStartUpdater else { return }
        updaterController.startUpdater()
        didStartUpdater = true
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        buildConfiguration.appcastURL(for: currentSettings).absoluteString
    }
}
