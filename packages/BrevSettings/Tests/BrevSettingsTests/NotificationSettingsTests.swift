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

@Suite("NotificationSettings")
struct NotificationSettingsTests {
    @Test("legacy push preference migrates to local notifications")
    func legacyPushPreferenceMigratesToLocalNotifications() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(true, forKey: "notifications.pushEnabled")

        #expect(NotificationSettings.load(from: defaults).notificationsEnabled)
    }

    @Test("defaults keep notifications off and badge/sound on")
    func defaultsKeepNotificationsOffAndBadgeSoundOn() throws {
        let defaults = try Self.makeDefaults()
        let settings = NotificationSettings.load(from: defaults)

        #expect(settings.notificationsEnabled == false)
        #expect(settings.badgePolicy == .inboxUnread)
        #expect(settings.badgeEnabled == true)
        #expect(settings.soundEnabled == true)
        #expect(settings.showPreviews == true)
        #expect(settings.accountOverrides.isEmpty)
        #expect(settings.quietHoursEnabled == false)
        #expect(settings.quietHoursStart == 22)
        #expect(settings.quietHoursEnd == 7)
    }

    @Test("saving and loading preserves every notification option")
    func savingAndLoadingPreservesEveryNotificationOption() throws {
        let defaults = try Self.makeDefaults()
        let settings = NotificationSettings(
            notificationsEnabled: true,
            badgeEnabled: false,
            badgePolicy: .selectedSources,
            soundEnabled: false,
            showPreviews: false,
            accountOverrides: [
                "acct-1": NotificationSettings.AccountOverride(
                    accountID: "acct-1",
                    notificationsEnabled: false,
                    badgeEnabled: true,
                    soundEnabled: false
                )
            ],
            quietHoursEnabled: true,
            quietHoursStart: 21,
            quietHoursEnd: 8
        )

        settings.save(to: defaults)
        let restored = NotificationSettings.load(from: defaults)

        #expect(restored == settings)
    }

    @Test("notification settings change signal has a stable name")
    func notificationSettingsChangeSignalHasStableName() {
        #expect(Notification.Name.brevNotificationSettingsDidChange.rawValue == "eu.brevmail.settings.notifications.changed")
    }

    @Test("corrupt persisted notification data falls back to defaults")
    func corruptPersistedNotificationDataFallsBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("not-a-bool", forKey: NotificationSettings.Key.notificationsEnabled)

        let settings = NotificationSettings.load(from: defaults)

        #expect(settings.notificationsEnabled == NotificationSettings.defaults.notificationsEnabled)
        #expect(settings.badgeEnabled == NotificationSettings.defaults.badgeEnabled)
        #expect(settings.badgePolicy == NotificationSettings.defaults.badgePolicy)
    }

    @Test("invalid badge policy falls back to defaults")
    func invalidBadgePolicyFallsBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("every-envelope-ever", forKey: NotificationSettings.Key.badgePolicy)

        let settings = NotificationSettings.load(from: defaults)

        #expect(settings.badgePolicy == NotificationSettings.defaults.badgePolicy)
    }

    @Test("account overrides can be added updated and removed")
    func accountOverridesCanBeAddedUpdatedAndRemoved() throws {
        var settings = NotificationSettings.defaults

        settings.setAccountOverride(
            accountID: "acct-1",
            notificationsEnabled: false,
            badgeEnabled: true,
            soundEnabled: false
        )

        #expect(settings.accountOverrides["acct-1"]?.notificationsEnabled == false)
        #expect(settings.accountOverrides["acct-1"]?.badgeEnabled == true)
        #expect(settings.accountOverrides["acct-1"]?.soundEnabled == false)

        settings.setAccountOverride(
            accountID: "acct-1",
            notificationsEnabled: true,
            badgeEnabled: false,
            soundEnabled: true
        )

        #expect(settings.accountOverrides["acct-1"]?.notificationsEnabled == true)
        #expect(settings.accountOverrides["acct-1"]?.badgeEnabled == false)
        #expect(settings.accountOverrides["acct-1"]?.soundEnabled == true)

        settings.removeAccountOverride(accountID: "acct-1")

        #expect(settings.accountOverrides.isEmpty)
    }

    @Test("account overrides persist through save and load")
    func accountOverridesPersistThroughSaveAndLoad() throws {
        let defaults = try Self.makeDefaults()
        var settings = NotificationSettings.defaults
        settings.setAccountOverride(
            accountID: "acct-1",
            notificationsEnabled: false,
            badgeEnabled: false,
            soundEnabled: false
        )

        settings.save(to: defaults)
        let restored = NotificationSettings.load(from: defaults)

        #expect(restored.accountOverrides == settings.accountOverrides)
    }

    @Test("quiet hours labels format correctly")
    func quietHoursLabelsFormatCorrectly() throws {
        let settings = NotificationSettings(
            notificationsEnabled: false,
            badgeEnabled: true,
            badgePolicy: .inboxUnread,
            soundEnabled: true,
            showPreviews: true,
            accountOverrides: [:],
            quietHoursEnabled: false,
            quietHoursStart: 0,
            quietHoursEnd: 12
        )

        #expect(settings.quietHoursStartLabel == "12:00 AM")
        #expect(settings.quietHoursEndLabel == "12:00 PM")
    }

    @Test("quiet hours labels format PM hours correctly")
    func quietHoursLabelsFormatPMHoursCorrectly() throws {
        let settings = NotificationSettings(
            notificationsEnabled: false,
            badgeEnabled: true,
            badgePolicy: .inboxUnread,
            soundEnabled: true,
            showPreviews: true,
            accountOverrides: [:],
            quietHoursEnabled: false,
            quietHoursStart: 13,
            quietHoursEnd: 23
        )

        #expect(settings.quietHoursStartLabel == "1:00 PM")
        #expect(settings.quietHoursEndLabel == "11:00 PM")
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "NotificationSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
