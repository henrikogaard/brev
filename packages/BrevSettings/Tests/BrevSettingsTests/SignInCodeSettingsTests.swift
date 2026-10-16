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

@Suite("Device-local sign-in consent")
struct SignInCodeSettingsTests {
    private let accountA = "imap-smtp:consent-a@example.test"
    private let accountB = "gmail:consent-b@example.test"

    @Test("Consent is off by default and independent by account and kind")
    func independentConsent() {
        var settings = SignInCodeSettings.defaults
        #expect(!settings.accountOverride(for: accountA).codesEnabled)
        #expect(!settings.accountOverride(for: accountA).linksEnabled)
        settings.setAccountOverride(accountID: accountA, codesEnabled: true, linksEnabled: false)
        settings.setAccountOverride(accountID: accountB, codesEnabled: false, linksEnabled: true)
        #expect(settings.accountOverride(for: accountA).codesEnabled)
        #expect(!settings.accountOverride(for: accountA).linksEnabled)
        #expect(!settings.accountOverride(for: accountB).codesEnabled)
        #expect(settings.accountOverride(for: accountB).linksEnabled)
        #expect(!settings.accountOverride(for: "new-account").codesEnabled)
        #expect(!settings.accountOverride(for: "new-account").linksEnabled)
        settings.setAccountOverride(accountID: accountA, codesEnabled: false, linksEnabled: false)
        #expect(!settings.accountOverride(for: accountA).codesEnabled)
        #expect(settings.accountOverride(for: accountB).linksEnabled)
        #expect(SignInCodeSettings.leavesMessageUnchanged)
        #expect(SignInCodeSettings.panelTimeout == 60)
    }

    @Test("Persistence writes only the supplied local defaults")
    func persistence() throws {
        let suite = "SignInCodeSettings-\(UUID().uuidString)"
        let otherSuite = suite + "-other"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let other = try #require(UserDefaults(suiteName: otherSuite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            other.removePersistentDomain(forName: otherSuite)
        }
        let standardBefore = UserDefaults.standard.object(forKey: SignInCodeSettings.Key.accountOverrides) as? NSObject
        #expect(SignInCodeSettings.load(from: defaults) == .defaults)
        var settings = SignInCodeSettings.defaults
        settings.setAccountOverride(accountID: accountA, codesEnabled: true, linksEnabled: false)
        settings.save(to: defaults)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(SignInCodeSettings.load(from: reopened) == settings)
        #expect(SignInCodeSettings.load(from: other) == .defaults)
        #expect(UserDefaults.standard.object(forKey: SignInCodeSettings.Key.accountOverrides) as? NSObject == standardBefore)
        #expect(Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? []) ==
            [SignInCodeSettings.Key.accountOverrides])
    }

    @Test("Missing, malformed and mismatched records fail closed", arguments: [
        "not json", "[]", "null",
        #"{"account":{"accountID":"account","codesEnabled":true}}"#,
        #"{"account":{"accountID":"account","codesEnabled":1,"linksEnabled":true}}"#,
        #"{"account":{"accountID":"account","codesEnabled":"true","linksEnabled":true}}"#,
        #"{"account":{"accountID":"different","codesEnabled":true,"linksEnabled":true}}"#,
        #"{"":{"accountID":"","codesEnabled":true,"linksEnabled":true}}"#,
        #"{"account":{"accountID":"account","codesEnabled":true,"linksEnabled":true},"bad":null}"#
    ])
    func malformedData(_ json: String) throws {
        let suite = "SignInCodeSettings-invalid-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(json.utf8), forKey: SignInCodeSettings.Key.accountOverrides)
        #expect(SignInCodeSettings.load(from: defaults) == .defaults)
        defaults.set(true, forKey: SignInCodeSettings.Key.accountOverrides)
        #expect(SignInCodeSettings.load(from: defaults) == .defaults)
    }

    @Test("Explicit removal deletes stored consent without changing another account")
    func removal() throws {
        let suite = "SignInCodeSettings-removal-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = SignInCodeSettings.defaults
        settings.setAccountOverride(accountID: accountA, codesEnabled: true, linksEnabled: true)
        settings.setAccountOverride(accountID: accountB, codesEnabled: false, linksEnabled: true)
        settings.save(to: defaults)
        settings.removeAccountOverride(accountID: accountA, from: defaults)
        let reloaded = SignInCodeSettings.load(from: defaults)
        #expect(reloaded.accountOverrides[accountA] == nil)
        #expect(!reloaded.accountOverride(for: accountA).codesEnabled)
        #expect(!reloaded.accountOverride(for: accountA).linksEnabled)
        #expect(reloaded.accountOverride(for: accountB).linksEnabled)
        let data = try #require(defaults.data(forKey: SignInCodeSettings.Key.accountOverrides))
        let records = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(records[accountA] == nil)
        settings.removeAccountOverride(accountID: accountB, from: defaults)
        #expect(defaults.object(forKey: SignInCodeSettings.Key.accountOverrides) == nil)
    }

    @Test("Backup and cloud allowlists cannot carry or restore sign-in consent", arguments: [BackupRestoreMode.merge, .replace])
    func backupExclusion(_ mode: BackupRestoreMode) throws {
        let suite = "SignInCodeSettings-backup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsPersistenceStore(defaults: defaults)
        let relatedConsent = RelatedConversationConsentStore(defaults: defaults)
        var local = SignInCodeSettings.defaults
        local.setAccountOverride(accountID: accountA, codesEnabled: true, linksEnabled: false)
        local.save(to: defaults)
        let before = defaults.data(forKey: SignInCodeSettings.Key.accountOverrides)
        let payload = SettingsBackupCodec.export(from: store, consentStore: relatedConsent, accountIDs: [accountA, accountB])
        let data = try JSONEncoder().encode(payload)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains(accountA))
        #expect(!json.contains("signInCode"))
        #expect(!SettingsBackupPayload.knownKeys.contains("signInCodeSettings"))
        #expect(!PreferenceSyncAllowlist.keys.contains(SignInCodeSettings.Key.accountOverrides))

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let injected: [String: Any] = [accountA: ["accountID": accountA, "codesEnabled": false, "linksEnabled": true],
                                       accountB: ["accountID": accountB, "codesEnabled": true, "linksEnabled": true]]
        object["signInCodeSettings"] = ["accountOverrides": injected]
        object[SignInCodeSettings.Key.accountOverrides] = injected
        let imported = try JSONDecoder().decode(SettingsBackupPayload.self, from: JSONSerialization.data(withJSONObject: object))
        SettingsBackupCodec.apply(imported, to: store, mode: mode, consentStore: relatedConsent)
        #expect(defaults.data(forKey: SignInCodeSettings.Key.accountOverrides) == before)
        #expect(SignInCodeSettings.load(from: defaults) == local)
        #expect(!SignInCodeSettings.load(from: defaults).accountOverride(for: accountB).codesEnabled)
        #expect(!SignInCodeSettings.load(from: defaults).accountOverride(for: accountB).linksEnabled)
        defaults.removeObject(forKey: SignInCodeSettings.Key.accountOverrides)
        SettingsBackupCodec.apply(imported, to: store, mode: mode, consentStore: relatedConsent)
        #expect(defaults.object(forKey: SignInCodeSettings.Key.accountOverrides) == nil)
        #expect(SignInCodeSettings.load(from: defaults) == .defaults)
    }
}
