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
@testable import BrevSettings
import Foundation
import Testing

@Suite("Closed-app push relay settings (#11)")
struct PushRelaySettingsTests {
    @Test("defaults are strictly off and round-trip locally without secrets")
    func defaultsOffAndLocalRoundTrip() throws {
        let suite = "PushRelaySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!NotificationSettings.defaults.notificationsEnabled)

        var settings = PushRelaySettings.load(from: defaults)
        #expect(!settings.isEnabled)
        #expect(settings.mode == .userHostedRelay)
        #expect(settings.endpointURLString.isEmpty)
        #expect(settings.enabledAccountIDs.isEmpty)
        #expect(settings.lastRegisteredAt == nil)
        #expect(settings.lastRegistrationError == nil)
        #expect(!settings.isAccountEnabled("acct-1"))

        settings.setAccount("acct-1", enabled: true)
        #expect(!settings.isAccountEnabled("acct-1")) // Master switch is still off.

        settings.isEnabled = true
        settings.mode = .jmapWebPush
        settings.endpointURLString = "https://push.example.com/jmap"
        settings.subscriptionID = "sub-42"
        settings.lastRegisteredAt = Date(timeIntervalSince1970: 1_750_000_000)
        settings.lastRegistrationError = nil
        #expect(settings.isAccountEnabled("acct-1"))
        #expect(!settings.isAccountEnabled("acct-2"))

        settings.save(to: defaults)

        let reloaded = PushRelaySettings.load(from: defaults)
        #expect(reloaded.isEnabled)
        #expect(reloaded.mode == .jmapWebPush)
        #expect(reloaded.endpointURLString == "https://push.example.com/jmap")
        #expect(reloaded.enabledAccountIDs == ["acct-1"])
        #expect(reloaded.subscriptionID == "sub-42")
        #expect(reloaded.lastRegisteredAt == Date(timeIntervalSince1970: 1_750_000_000))
        #expect(!reloaded.deviceClientID.isEmpty)

        // Removing an account clears its push relay opt-in.
        let store = SettingsPersistenceStore(defaults: defaults)
        store.removeAccountScopedState(accountID: "acct-1")
        let afterRemoval = PushRelaySettings.load(from: defaults)
        #expect(!afterRemoval.enabledAccountIDs.contains("acct-1"))
    }

    @Test("push relay settings are excluded from settings backups and iCloud preference sync")
    func excludedFromBackupAndPreferenceSync() throws {
        let suite = "PushRelayBackupExclusion-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = PushRelaySettings.defaults
        settings.isEnabled = true
        settings.mode = .userHostedRelay
        settings.endpointURLString = "https://private-relay.example.net/hook"
        settings.enabledAccountIDs = ["acct-push-only"]
        settings.subscriptionID = "sub-device-local"
        settings.save(to: defaults)

        let store = SettingsPersistenceStore(defaults: defaults)
        let relatedConsent = RelatedConversationConsentStore(defaults: defaults)
        let backup = SettingsBackupCodec.export(
            from: store,
            consentStore: relatedConsent,
            accountIDs: ["acct-push-only"]
        )
        let encoded = try JSONEncoder().encode(backup)
        let jsonText = String(decoding: encoded, as: UTF8.self)
        #expect(!jsonText.contains("pushRelay"))
        #expect(!jsonText.contains("private-relay.example.net"))
        #expect(!jsonText.contains("acct-push-only"))
        #expect(!jsonText.contains("sub-device-local"))

        let syncAllowlist = PreferenceSyncAllowlist.keys
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.isEnabled))
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.mode))
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.endpointURLString))
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.enabledAccountIDs))
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.deviceClientID))
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.subscriptionID))
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.lastRegisteredAt))
        #expect(!syncAllowlist.contains(PushRelaySettings.Key.lastRegistrationError))
    }

    @Test("secret store keeps bearer token and RFC 8291 key material out of UserDefaults")
    func secretStoreRoundTripAndClear() throws {
        let secretStore = InMemoryPushRelaySecretStore()
        #expect(try secretStore.bearerToken() == nil)
        #expect(try secretStore.encryptionKeyMaterial() == nil)

        try secretStore.saveBearerToken("  secret-bearer-token  ")
        #expect(try secretStore.bearerToken() == "secret-bearer-token")

        let firstKey = try secretStore.loadOrCreateEncryptionKeyMaterial()
        let secondKey = try secretStore.loadOrCreateEncryptionKeyMaterial()
        #expect(firstKey == secondKey)

        try secretStore.saveBearerToken("   ")
        #expect(try secretStore.bearerToken() == nil)

        try secretStore.clearAll()
        #expect(try secretStore.bearerToken() == nil)
        #expect(try secretStore.encryptionKeyMaterial() == nil)
    }

    @Test("settings search indexes Closed-App Push under Notifications")
    func settingsSearchIndexesPushRelay() {
        let titles = SettingsSection.notifications.searchableControlTitles
        #expect(titles.contains(String(localized: "Closed-App Push (Self-Hosted)", bundle: .module)))
        #expect(titles.contains(String(localized: "JMAP WebPush", bundle: .module)))
    }
}
