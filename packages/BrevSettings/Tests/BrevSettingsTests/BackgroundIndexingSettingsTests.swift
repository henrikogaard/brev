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

@testable import BrevSettings
import Foundation
import Testing

@Suite("BackgroundIndexingSettings")
struct BackgroundIndexingSettingsTests {
    private func makeDefaults(_ suffix: String) throws -> (UserDefaults, String) {
        let suite = "BackgroundIndexingSettingsTests-\(suffix)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test("defaults keep background indexing strictly off with conservative sub-options")
    func defaultsAreStrictlyOptIn() throws {
        let (defaults, suite) = try makeDefaults("defaults")
        defer { defaults.removePersistentDomain(forName: suite) }

        let loaded = BackgroundIndexingSettings.load(from: defaults)
        #expect(loaded == .defaults)
        #expect(loaded.isEnabled == false)
        #expect(loaded.windowDays == .days90)
        #expect(loaded.indexAttachments == true)
        #expect(loaded.requireUnmeteredNetworkAndPower == true)
    }

    @Test("settings persist and round-trip across all lookback windows")
    func persistenceRoundTrip() throws {
        let (defaults, suite) = try makeDefaults("roundtrip")
        defer { defaults.removePersistentDomain(forName: suite) }

        for window in BackgroundIndexingWindow.allCases {
            let expected = BackgroundIndexingSettings(
                isEnabled: true,
                windowDays: window,
                indexAttachments: window != .days365,
                requireUnmeteredNetworkAndPower: window == .days30
            )
            expected.save(to: defaults)
            #expect(BackgroundIndexingSettings.load(from: defaults) == expected)
        }
    }

    @Test("SettingsBackupCodec restores preferences without silently enabling background indexing")
    func backupCodecRoundTrip() throws {
        let (sourceDefaults, sourceSuite) = try makeDefaults("backup-src")
        let (targetDefaults, targetSuite) = try makeDefaults("backup-dst")
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            targetDefaults.removePersistentDomain(forName: targetSuite)
        }

        let sourceStore = SettingsPersistenceStore(defaults: sourceDefaults)
        let targetStore = SettingsPersistenceStore(defaults: targetDefaults)
        let custom = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days365,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: false
        )
        sourceStore.save(custom)

        let payload = SettingsBackupCodec.export(from: sourceStore)
        #expect(payload.backgroundIndexing == BackgroundIndexingBackupSettings(custom))
        #expect(SettingsBackupPayload.knownKeys.contains("backgroundIndexing"))

        // Target starts with default (isEnabled == false): restore must NOT flip isEnabled to true.
        SettingsBackupCodec.apply(payload, to: targetStore, mode: .replace)
        let restored = targetStore.backgroundIndexingSettings()
        #expect(restored.isEnabled == false)
        #expect(restored.windowDays == .days365)
        #expect(restored.indexAttachments == false)
        #expect(restored.requireUnmeteredNetworkAndPower == false)

        // When target already opted in locally, restore preserves local isEnabled == true.
        targetStore.save(BackgroundIndexingSettings(isEnabled: true, windowDays: .days30))
        SettingsBackupCodec.apply(payload, to: targetStore, mode: .replace)
        let preserved = targetStore.backgroundIndexingSettings()
        #expect(preserved.isEnabled == true)
        #expect(preserved.windowDays == .days365)
    }

    @Test("background indexing keys stay excluded from iCloud preference sync")
    func excludedFromICloudPreferenceSync() {
        let syncedKeys = Set(PreferenceSyncAllowlist.keys)
        #expect(!syncedKeys.contains(BackgroundIndexingSettings.Key.isEnabled))
        #expect(!syncedKeys.contains(BackgroundIndexingSettings.Key.windowDays))
        #expect(!syncedKeys.contains(BackgroundIndexingSettings.Key.indexAttachments))
        #expect(!syncedKeys.contains(BackgroundIndexingSettings.Key.requireUnmeteredNetworkAndPower))
    }

    @Test("progress store persists per-account state and clears on account removal")
    func progressStoreLifecycle() throws {
        let (defaults, suite) = try makeDefaults("progress")
        defer { defaults.removePersistentDomain(forName: suite) }

        let progressStore = BackgroundIndexingProgressStore(defaults: defaults)
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let progress = BackgroundIndexingAccountProgress(
            indexedBodyMessageIDs: ["m1", "m2"],
            indexedAttachmentMessageIDs: ["m1"],
            ftsIndexedAttachmentIDsByMessage: ["m1": ["a1"]],
            skippedAttachmentIDsByMessage: ["m2": ["a2"]],
            lastIndexedAt: timestamp
        )
        progressStore.save(progress, accountID: "acct-a")
        #expect(progressStore.load(accountID: "acct-a") == progress)
        #expect(progressStore.latestIndexedAt() == timestamp)

        progressStore.clearAttachmentProgress(accountID: "acct-a")
        let afterAttachmentClear = progressStore.load(accountID: "acct-a")
        #expect(afterAttachmentClear.indexedBodyMessageIDs == ["m1", "m2"])
        #expect(afterAttachmentClear.indexedAttachmentMessageIDs.isEmpty)
        #expect(afterAttachmentClear.ftsIndexedAttachmentIDsByMessage.isEmpty)
        #expect(afterAttachmentClear.skippedAttachmentIDsByMessage.isEmpty)

        SettingsPersistenceStore(defaults: defaults).removeAccountScopedState(accountID: "acct-a")
        #expect(progressStore.load(accountID: "acct-a") == .empty)
    }

    @Test("status presentation covers idle, running, paused, completed, and failed states")
    func statusPresentationFormatting() {
        let disabled = BackgroundIndexingSettings.defaults
        #expect(BackgroundIndexingStatusPresentation.summary(settings: disabled, status: .idle).contains("Off."))
        #expect(BackgroundIndexingStatusPresentation.tone(settings: disabled, status: .idle) == .info)

        let enabled = BackgroundIndexingSettings(isEnabled: true)
        let running = BackgroundIndexingStatus(state: .running(completed: 5, total: 20))
        #expect(BackgroundIndexingStatusPresentation.summary(settings: enabled, status: running).contains("5"))
        #expect(BackgroundIndexingStatusPresentation.summary(settings: enabled, status: running).contains("20"))
        #expect(BackgroundIndexingStatusPresentation.isRunning(running.state))

        let metered = BackgroundIndexingStatus(state: .paused(.meteredNetwork))
        #expect(BackgroundIndexingStatusPresentation.tone(settings: enabled, status: metered) == .warning)
        #expect(BackgroundIndexingStatusPresentation.summary(settings: enabled, status: metered).contains("cellular"))

        let lowPower = BackgroundIndexingStatus(state: .paused(.lowPowerMode))
        #expect(BackgroundIndexingStatusPresentation.tone(settings: enabled, status: lowPower) == .warning)
        #expect(BackgroundIndexingStatusPresentation.summary(settings: enabled, status: lowPower).contains("Low Power Mode"))

        let completed = BackgroundIndexingStatus(
            state: .completed,
            indexedMessagesCount: 14,
            indexedAttachmentsCount: 3,
            pendingCount: 0,
            lastIndexedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        #expect(BackgroundIndexingStatusPresentation.tone(settings: enabled, status: completed) == .success)
        #expect(BackgroundIndexingStatusPresentation.summary(settings: enabled, status: completed).contains("14"))
        #expect(BackgroundIndexingStatusPresentation.summary(settings: enabled, status: completed).contains("3"))

        let failed = BackgroundIndexingStatus(state: .failed("network timeout"))
        #expect(BackgroundIndexingStatusPresentation.tone(settings: enabled, status: failed) == .warning)
        #expect(BackgroundIndexingStatusPresentation.summary(settings: enabled, status: failed).contains("network timeout"))
    }

    @Test("settings search indexes background indexing controls under Mail Storage")
    func settingsSearchFindsBackgroundIndexingControls() {
        let results = SettingsSearchResult.results(
            for: "background",
            sections: SettingsSection.allCases
        )
        #expect(results.contains { $0.section == .mailStorage && $0.title == "Background indexing" })
        #expect(results.contains {
            $0.section == .mailStorage && $0.title == "Index recent mail & attachments in background"
        })
    }
}
