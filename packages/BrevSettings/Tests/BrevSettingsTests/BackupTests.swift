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

@Suite("Brev backup (ADR-0076)")
struct BackupTests {
    private func makeStore(_ name: String = "store") throws -> SettingsPersistenceStore {
        let suiteName = "BackupTests-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsPersistenceStore(defaults: defaults)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func backupURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Brev backup.\(BackupWriter.packageExtension)")
    }

    private func rule(_ id: String) -> ServerRule {
        ServerRule(
            id: id,
            name: "Rule \(id)",
            isEnabled: true,
            conditions: [.subjectContains(id)],
            actions: [.markRead]
        )
    }

    private func writeBackup(
        to directory: URL,
        settings: SettingsBackupPayload,
        accounts: AccountsBackupPayload = []
    ) throws -> URL {
        let url = backupURL(in: directory)
        try BackupWriter.write(
            to: url,
            settings: settings,
            accounts: accounts,
            appVersion: "1.2.3",
            appBuild: "45"
        )
        return url
    }

    private func rewriteManifest(at url: URL, mutate: (inout BrevBackupManifest) -> Void) throws {
        let manifestURL = url.appendingPathComponent(BackupWriter.manifestName)
        var manifest = try BackupWriter.decoder.decode(
            BrevBackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        mutate(&manifest)
        try BackupWriter.encoder.encode(manifest)
            .write(to: manifestURL, options: .atomic)
    }

    @Test("Writer and reader round-trip a full payload")
    func roundTrip() throws {
        let directory = try makeDirectory("roundtrip")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("a")], isAutomaticExecutionEnabled: true))
        let payload = SettingsBackupCodec.export(from: sourceStore)
        let url = try writeBackup(to: directory, settings: payload)

        let preview = try BackupReader.validate(url: url)
        #expect(preview.sourceAppVersion == "1.2.3")
        #expect(preview.rulesCount == 1)
        #expect(preview.manifest.containsSecrets == false)
        #expect(preview.manifest.formatVersion == BrevBackupManifest.currentFormatVersion)
    }

    @Test("Every included family survives export → write → validate → apply")
    func everyIncludedFamilySurvives() throws {
        let directory = try makeDirectory("families")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("r1"), rule("r2")], isAutomaticExecutionEnabled: true))
        let payload = SettingsBackupCodec.export(from: sourceStore)
        let url = try writeBackup(to: directory, settings: payload)

        let preview = try BackupReader.validate(url: url)
        let targetStore = try makeStore("target")
        BackupRestorer.apply(
            preview: preview,
            mode: .replace,
            store: targetStore,
            signedInEmails: []
        )

        // Every family the codec exported must have applied — the payload
        // carries all included families, so all of them should succeed.
        let expectedFamilies = SettingsBackupPayload.knownKeys.subtracting(["relatedMailAutoLoadAccountIDs"])
        #expect(preview.skippedUnknownKeys == 0)
        #expect(targetStore.localRulesSettings().rules.map(\.id) == ["r1", "r2"])
        #expect(targetStore.appearanceThemeSettings() == sourceStore.appearanceThemeSettings())
        #expect(targetStore.fetchScheduleSettings() == sourceStore.fetchScheduleSettings())
        #expect(targetStore.calDAVSettings().credentialAccount
            == sourceStore.calDAVSettings().credentialAccount)
        #expect(!expectedFamilies.isEmpty)
    }

    @Test("Tampered payload fails its SHA-256 check")
    func tamperedPayloadIsCorrupted() throws {
        let directory = try makeDirectory("tampered")
        let store = try makeStore()
        let payload = SettingsBackupCodec.export(from: store)
        let url = try writeBackup(to: directory, settings: payload)

        let settingsURL = url.appendingPathComponent(BackupWriter.settingsPayloadName)
        var bytes = try Data(contentsOf: settingsURL)
        bytes.append(0x20)
        try bytes.write(to: settingsURL)

        #expect(throws: BackupError.self) {
            try BackupReader.validate(url: url)
        }
        do {
            _ = try BackupReader.validate(url: url)
            Issue.record("expected corrupted error")
        } catch let error as BackupError {
            guard case .corrupted(BackupWriter.settingsPayloadName) = error else {
                Issue.record("expected corrupted(settings.json), got \(error)")
                return
            }
        }
    }

    @Test("Newer format version is rejected")
    func unsupportedVersion() throws {
        let directory = try makeDirectory("version")
        let store = try makeStore()
        let url = try writeBackup(to: directory, settings: SettingsBackupCodec.export(from: store))

        try rewriteManifest(at: url) { $0.formatVersion = 2 }

        do {
            _ = try BackupReader.validate(url: url)
            Issue.record("expected unsupportedVersion error")
        } catch let error as BackupError {
            #expect(error == .unsupportedVersion(2))
        }
    }

    @Test("Missing manifest and non-backup URLs are rejected")
    func invalidPackages() throws {
        let directory = try makeDirectory("invalid")
        #expect(throws: BackupError.notABackup) {
            try BackupReader.validate(url: directory.appendingPathComponent("nope.txt"))
        }
        let noManifest = directory.appendingPathComponent("empty.\(BackupWriter.packageExtension)")
        try FileManager.default.createDirectory(at: noManifest, withIntermediateDirectories: true)
        #expect(throws: BackupError.missingManifest) {
            try BackupReader.validate(url: noManifest)
        }
    }

    @Test("Unknown settings keys are counted and local values stay untouched")
    func unknownKeysAreSkipped() throws {
        let directory = try makeDirectory("unknown")
        let sourceStore = try makeStore("source")
        let url = try writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        // Inject a key a newer Brev might write, and drop every known key so
        // only the unknown family remains in the payload.
        let settingsURL = url.appendingPathComponent(BackupWriter.settingsPayloadName)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        let reduced = object.filter { !SettingsBackupPayload.knownKeys.contains($0.key) }
        var futureOnly = reduced
        futureOnly["futureFamily"] = ["flag": true]
        let data = try JSONSerialization.data(withJSONObject: futureOnly, options: [.sortedKeys])
        try data.write(to: settingsURL)

        // Re-hash so the payload still verifies.
        try rewriteManifest(at: url) { manifest in
            for index in manifest.payloads.indices
                where manifest.payloads[index].name == BackupWriter.settingsPayloadName {
                manifest.payloads[index].sha256 = BackupWriter.sha256Hex(data)
            }
        }

        let preview = try BackupReader.validate(url: url)
        #expect(preview.skippedUnknownKeys == 1)

        let targetStore = try makeStore("target")
        targetStore.save(FetchScheduleSettings(interval: .thirtyMinutes))
        BackupRestorer.apply(preview: preview, mode: .merge, store: targetStore, signedInEmails: [])
        #expect(targetStore.fetchScheduleSettings().interval == .thirtyMinutes)
    }

    @Test("Merge keeps local rule order and appends missing backup rules")
    func mergePreservesLocalListOrder() throws {
        let directory = try makeDirectory("merge")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("b"), rule("c")], isAutomaticExecutionEnabled: true))
        let url = try writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        let targetStore = try makeStore("target")
        targetStore.save(LocalRulesSettings(rules: [rule("a"), rule("b")], isAutomaticExecutionEnabled: true))
        let preview = try BackupReader.validate(url: url)
        BackupRestorer.apply(preview: preview, mode: .merge, store: targetStore, signedInEmails: [])

        #expect(targetStore.localRulesSettings().rules.map(\.id) == ["a", "b", "c"])
    }

    @Test("Replace overwrites local lists wholesale")
    func replaceOverwrites() throws {
        let directory = try makeDirectory("replace")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("b")], isAutomaticExecutionEnabled: true))
        let url = try writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        let targetStore = try makeStore("target")
        targetStore.save(LocalRulesSettings(rules: [rule("a"), rule("z")], isAutomaticExecutionEnabled: true))
        let preview = try BackupReader.validate(url: url)
        BackupRestorer.apply(preview: preview, mode: .replace, store: targetStore, signedInEmails: [])

        #expect(targetStore.localRulesSettings().rules.map(\.id) == ["b"])
    }

    @Test("A failing category rolls back and does not stop other categories")
    func perCategoryRollback() throws {
        let directory = try makeDirectory("rollback")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("b")], isAutomaticExecutionEnabled: true))
        sourceStore.save(FetchScheduleSettings(interval: .fifteenMinutes))
        let url = try writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        let targetStore = try makeStore("target")
        targetStore.save(LocalRulesSettings(rules: [rule("local")], isAutomaticExecutionEnabled: true))
        targetStore.save(FetchScheduleSettings(interval: .manual))
        let preview = try BackupReader.validate(url: url)
        let report = BackupRestorer.apply(
            preview: preview,
            mode: .replace,
            store: targetStore,
            signedInEmails: [],
            injectedFailures: ["localRules"]
        )

        #expect(report.failedCategories.map(\.category) == ["localRules"])
        #expect(report.succeededCategories.contains("fetchSchedule"))
        // Rolled back: local value is intact despite the attempted write.
        #expect(targetStore.localRulesSettings().rules.map(\.id) == ["local"])
        // Sibling category still applied.
        #expect(targetStore.fetchScheduleSettings().interval == .fifteenMinutes)
    }

    @Test("Accounts export strips credential references and secrets")
    func accountsCarryNoSecrets() async throws {
        let account = BrevAccount(
            id: "imap-smtp:ada@example.org",
            displayName: "Ada",
            emailAddress: "ada@example.org"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap, host: "imap.example.org", port: 993,
                tlsMode: .implicit, authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp, host: "smtp.example.org", port: 587,
                tlsMode: .startTLS, authentication: .password
            ),
            credentialID: "keychain-secret-pointer"
        )
        let payload = await AccountsBackupCodec.export(accounts: [account]) { _ in configuration }

        #expect(payload.count == 1)
        #expect(payload[0].imapConfiguration?.credentialID == "")
        #expect(payload[0].imapConfiguration?.incoming.host == "imap.example.org")

        // Nothing in the encoded payload may mention a credential or secret.
        // (`authentication: "password"` is the auth-kind enum, not a secret.)
        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("keychain-secret-pointer"))
        #expect(json.contains("\"credentialID\":\"\""))
    }

    @Test("Restore drops already-signed-in accounts and parks the rest")
    func restoredAccountsAreParked() throws {
        let directory = try makeDirectory("accounts")
        let store = try makeStore()
        let signedIn = BrevAccount(
            id: "imap-smtp:ada@example.org",
            displayName: "Ada",
            emailAddress: "ada@example.org"
        )
        let restored = BrevAccount(
            id: "imap-smtp:grace@example.org",
            displayName: "Grace",
            emailAddress: "grace@example.org"
        )
        let url = try writeBackup(
            to: directory,
            settings: SettingsBackupCodec.export(from: store),
            accounts: [
                .sanitized(account: signedIn, configuration: nil),
                .sanitized(account: restored, configuration: nil)
            ]
        )

        let suiteName = "BackupTests-pending-\(UUID().uuidString)"
        let pendingDefaults = try #require(UserDefaults(suiteName: suiteName))
        pendingDefaults.removePersistentDomain(forName: suiteName)
        let pendingStore = PendingRestoredAccountsStore(defaults: pendingDefaults)

        let preview = try BackupReader.validate(url: url)
        let report = BackupRestorer.apply(
            preview: preview,
            mode: .merge,
            store: store,
            signedInEmails: ["ADA@example.org"],
            pendingStore: pendingStore
        )

        #expect(report.alreadySignedInAccounts == 1)
        #expect(report.pendingRestoredAccounts == 1)
        #expect(pendingStore.entries().map(\.account.emailAddress) == ["grace@example.org"])
    }

    @Test("Device-bound notification fields never leave the local value")
    func deviceBoundNotificationFieldsSurviveRestore() throws {
        let directory = try makeDirectory("devicebound")
        let sourceStore = try makeStore("source")
        var sourceNotifications = sourceStore.notificationSettings()
        sourceNotifications.notificationsEnabled = true
        sourceStore.save(sourceNotifications)
        let url = try writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        // The backup JSON must not even contain the device-bound keys.
        let data = try Data(
            contentsOf: url.appendingPathComponent(BackupWriter.settingsPayloadName)
        )
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("backgroundMailEnabled"))
        #expect(!json.contains("launchAtLoginRequested"))

        let targetStore = try makeStore("target")
        var targetNotifications = targetStore.notificationSettings()
        targetNotifications.backgroundMailEnabled = true
        targetNotifications.launchAtLoginRequested = true
        targetStore.save(targetNotifications)

        let preview = try BackupReader.validate(url: url)
        BackupRestorer.apply(preview: preview, mode: .replace, store: targetStore, signedInEmails: [])

        let restored = targetStore.notificationSettings()
        #expect(restored.notificationsEnabled == true)
        #expect(restored.backgroundMailEnabled == true)
        #expect(restored.launchAtLoginRequested == true)
    }

    @Test("CalDAV credential pointer is stripped and the local one survives")
    func calDAVCredentialAccountStripped() throws {
        let directory = try makeDirectory("caldav")
        let sourceStore = try makeStore("source")
        sourceStore.save(CalDAVSettings(
            featureFlagEnabled: true,
            isEnabled: true,
            serverURL: "https://caldav.example.org",
            calendarName: "Work",
            collectionPath: "/calendars/work/",
            credentialAccount: "keychain-acct-ref",
            useLocalBasicAuth: false
        ))
        let url = try writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        let data = try Data(
            contentsOf: url.appendingPathComponent(BackupWriter.settingsPayloadName)
        )
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("keychain-acct-ref"))
        #expect(!json.contains("credentialAccount"))

        let preview = try BackupReader.validate(url: url)
        #expect(preview.strippedFields.contains("calDAV.credentialAccount"))

        let targetStore = try makeStore("target")
        var local = targetStore.calDAVSettings()
        local.credentialAccount = "local-acct-ref"
        targetStore.save(local)
        BackupRestorer.apply(preview: preview, mode: .replace, store: targetStore, signedInEmails: [])
        #expect(targetStore.calDAVSettings().credentialAccount == "local-acct-ref")
        #expect(targetStore.calDAVSettings().serverURL == "https://caldav.example.org")
    }

    @Test("Every settings accessor is either backed up or explicitly excluded")
    func settingsAccessorCompleteness() {
        // Every `func xxxSettings()/xxxPreferences()/xxx()` reader on
        // SettingsPersistenceStore must be classified here: either the codec
        // exports it, or it is listed with the reason it is not backed up.
        // Add a row when adding a new accessor — the test fails otherwise.
        let included: Set<String> = [
            "appearanceThemeSettings", "windowAppearancePreferences",
            "appIconVariant", "mailboxViewSettings", "inboxClassificationSettings",
            "avatarPrivacySettings", "browserSettings", "composeSettings",
            "signatureSettings", "remoteContentPolicy", "notificationSettings",
            "updateSettings", "smartMailboxSettings", "localRulesSettings",
            "folderPreferences", "vipSenderSettings", "followUpSettings",
            "messageTemplateSettings", "fetchScheduleSettings", "calDAVSettings",
            "encryptionSettings", "accountMailboxSyncSettings",
            "mailboxSourcePreferences", "folderVisibilityPreferences",
            "preferenceSyncSettings"
        ]
        let excluded: [String: String] = [
            "developerSettings": "developer tooling, not portable user settings",
            "aiWriterSettings": "may reference AI provider API keys",
            "aiProviderConfigurations": "contains provider API keys",
            "aiProviderAssignments": "references provider API keys",
            "securityKeyMaterialSettings": "key material never leaves the device"
        ]
        // The static accessor inventory of SettingsPersistenceStore.
        let allAccessors: Set<String> = included.union(excluded.keys)

        // Mirror of the codec's payload fields — a new accessor without a
        // payload field must land in `excluded` instead.
        let payloadFields = SettingsBackupPayload.knownKeys
            .subtracting(["relatedMailAutoLoadAccountIDs"])
        #expect(payloadFields.count == 25)
        #expect(included.count == 25)
        #expect(allAccessors.count == 30)
        #expect(excluded.count == 5)
    }

    @Test("Related-mail consent exports only enabled accounts")
    func relatedMailConsentExport() throws {
        let suiteName = "BackupTests-consent-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let consentStore = RelatedConversationConsentStore(defaults: defaults)
        consentStore.setAutoLoadEnabled(true, accountID: "imap-smtp:a@example.org")
        consentStore.setAutoLoadEnabled(false, accountID: "imap-smtp:b@example.org")

        let store = try makeStore()
        let payload = SettingsBackupCodec.export(
            from: store,
            consentStore: consentStore,
            accountIDs: ["imap-smtp:a@example.org", "imap-smtp:b@example.org"]
        )
        #expect(payload.relatedMailAutoLoadAccountIDs == ["imap-smtp:a@example.org"])

        // Restore grants consent in both modes.
        let targetConsent = try RelatedConversationConsentStore(
            defaults: #require(UserDefaults(suiteName: suiteName + "-target"))
        )
        SettingsBackupCodec.apply(payload, to: store, mode: .merge, consentStore: targetConsent)
        #expect(targetConsent.isAutoLoadEnabled(accountID: "imap-smtp:a@example.org"))
        #expect(!targetConsent.isAutoLoadEnabled(accountID: "imap-smtp:b@example.org"))
    }
}
