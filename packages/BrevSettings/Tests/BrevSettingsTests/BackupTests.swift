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
import CryptoKit
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

    private func makeDirectory(_ name: String) async throws -> URL {
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
        accounts: AccountsBackupPayload = [],
        mailPayloads: [BackupWriter.MailFile] = []
    ) async throws -> URL {
        let url = backupURL(in: directory)
        try await BackupWriter.write(
            to: url,
            settings: settings,
            accounts: accounts,
            appVersion: "1.2.3",
            appBuild: "45",
            mailPayloads: mailPayloads
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
    func roundTrip() async throws {
        let directory = try await makeDirectory("roundtrip")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("a")], isAutomaticExecutionEnabled: true))
        let payload = SettingsBackupCodec.export(from: sourceStore)
        let url = try await writeBackup(to: directory, settings: payload)

        let preview = try BackupReader.validate(url: url)
        #expect(preview.sourceAppVersion == "1.2.3")
        #expect(preview.rulesCount == 1)
        #expect(preview.manifest.containsSecrets == false)
        #expect(preview.manifest.formatVersion == BrevBackupManifest.currentFormatVersion)
    }

    @Test("Every included family survives export → write → validate → apply")
    func everyIncludedFamilySurvives() async throws {
        let directory = try await makeDirectory("families")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("r1"), rule("r2")], isAutomaticExecutionEnabled: true))
        let payload = SettingsBackupCodec.export(from: sourceStore)
        let url = try await writeBackup(to: directory, settings: payload)

        let preview = try BackupReader.validate(url: url)
        let targetStore = try makeStore("target")
        await BackupRestorer.apply(
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
    func tamperedPayloadIsCorrupted() async throws {
        let directory = try await makeDirectory("tampered")
        let store = try makeStore()
        let payload = SettingsBackupCodec.export(from: store)
        let url = try await writeBackup(to: directory, settings: payload)

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
    func unsupportedVersion() async throws {
        let directory = try await makeDirectory("version")
        let store = try makeStore()
        let url = try await writeBackup(to: directory, settings: SettingsBackupCodec.export(from: store))

        let tooNew = BrevBackupManifest.currentFormatVersion + 1
        try rewriteManifest(at: url) { $0.formatVersion = tooNew }

        do {
            _ = try BackupReader.validate(url: url)
            Issue.record("expected unsupportedVersion error")
        } catch let error as BackupError {
            #expect(error == .unsupportedVersion(tooNew))
        }
    }

    @Test("Missing manifest and non-backup URLs are rejected")
    func invalidPackages() async throws {
        let directory = try await makeDirectory("invalid")
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
    func unknownKeysAreSkipped() async throws {
        let directory = try await makeDirectory("unknown")
        let sourceStore = try makeStore("source")
        let url = try await writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

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
        await BackupRestorer.apply(preview: preview, mode: .merge, store: targetStore, signedInEmails: [])
        #expect(targetStore.fetchScheduleSettings().interval == .thirtyMinutes)
    }

    @Test("Merge keeps local rule order and appends missing backup rules")
    func mergePreservesLocalListOrder() async throws {
        let directory = try await makeDirectory("merge")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("b"), rule("c")], isAutomaticExecutionEnabled: true))
        let url = try await writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        let targetStore = try makeStore("target")
        targetStore.save(LocalRulesSettings(rules: [rule("a"), rule("b")], isAutomaticExecutionEnabled: true))
        let preview = try BackupReader.validate(url: url)
        await BackupRestorer.apply(preview: preview, mode: .merge, store: targetStore, signedInEmails: [])

        #expect(targetStore.localRulesSettings().rules.map(\.id) == ["a", "b", "c"])
    }

    @Test("Replace overwrites local lists wholesale")
    func replaceOverwrites() async throws {
        let directory = try await makeDirectory("replace")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("b")], isAutomaticExecutionEnabled: true))
        let url = try await writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        let targetStore = try makeStore("target")
        targetStore.save(LocalRulesSettings(rules: [rule("a"), rule("z")], isAutomaticExecutionEnabled: true))
        let preview = try BackupReader.validate(url: url)
        await BackupRestorer.apply(preview: preview, mode: .replace, store: targetStore, signedInEmails: [])

        #expect(targetStore.localRulesSettings().rules.map(\.id) == ["b"])
    }

    @Test("A failing category rolls back and does not stop other categories")
    func perCategoryRollback() async throws {
        let directory = try await makeDirectory("rollback")
        let sourceStore = try makeStore("source")
        sourceStore.save(LocalRulesSettings(rules: [rule("b")], isAutomaticExecutionEnabled: true))
        sourceStore.save(FetchScheduleSettings(interval: .fifteenMinutes))
        let url = try await writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

        let targetStore = try makeStore("target")
        targetStore.save(LocalRulesSettings(rules: [rule("local")], isAutomaticExecutionEnabled: true))
        targetStore.save(FetchScheduleSettings(interval: .manual))
        let preview = try BackupReader.validate(url: url)
        let report = await BackupRestorer.apply(
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
    func restoredAccountsAreParked() async throws {
        let directory = try await makeDirectory("accounts")
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
        let url = try await writeBackup(
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
        let report = await BackupRestorer.apply(
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
    func deviceBoundNotificationFieldsSurviveRestore() async throws {
        let directory = try await makeDirectory("devicebound")
        let sourceStore = try makeStore("source")
        var sourceNotifications = sourceStore.notificationSettings()
        sourceNotifications.notificationsEnabled = true
        sourceStore.save(sourceNotifications)
        let url = try await writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

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
        await BackupRestorer.apply(preview: preview, mode: .replace, store: targetStore, signedInEmails: [])

        let restored = targetStore.notificationSettings()
        #expect(restored.notificationsEnabled == true)
        #expect(restored.backgroundMailEnabled == true)
        #expect(restored.launchAtLoginRequested == true)
    }

    @Test("CalDAV credential pointer is stripped and the local one survives")
    func calDAVCredentialAccountStripped() async throws {
        let directory = try await makeDirectory("caldav")
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
        let url = try await writeBackup(to: directory, settings: SettingsBackupCodec.export(from: sourceStore))

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
        await BackupRestorer.apply(preview: preview, mode: .replace, store: targetStore, signedInEmails: [])
        #expect(targetStore.calDAVSettings().credentialAccount == "local-acct-ref")
        #expect(targetStore.calDAVSettings().serverURL == "https://caldav.example.org")
    }

    @Test("Every settings accessor is either backed up or explicitly excluded")
    func settingsAccessorCompleteness() async {
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
    func relatedMailConsentExport() async throws {
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

    // MARK: - Local mail payloads (ADR-0077)

    private func makeLocalBackend(_ name: String) throws -> (LocalMailBackend, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupTests-local-\(name)-\(UUID().uuidString)")
        return (LocalMailBackend(store: LocalMaildirStore(rootURL: root)), root)
    }

    private func mboxFile(body: String, messageID: String) -> BackupWriter.MailFile {
        BackupWriter.MailFile(name: "mail/archive.mbox", folderName: "Archive") { url in
            let mbox = """
            From alice@example.org Tue Sep 16 10:30:00 2026
            From: Alice <alice@example.org>
            Subject: Kept mail
            Date: Tue, 16 Sep 2026 10:30:00 +0000
            Message-ID: \(messageID)

            \(body)
            """
            try Data(mbox.utf8).write(to: url)
        }
    }

    @Test("Writer includes mail/*.mbox payloads with verified hashes")
    func writerIncludesMailPayloads() async throws {
        let directory = try await makeDirectory("mail")
        let url = try await writeBackup(
            to: directory,
            settings: SettingsBackupCodec.export(from: makeStore("source")),
            mailPayloads: [mboxFile(body: "hello", messageID: "<m1@example.org>")]
        )
        let preview = try BackupReader.validate(url: url)
        #expect(preview.mailFolderCount == 1)
        #expect(preview.mailPayloads.first?.folderName == "Archive")
        #expect(preview.mailBytes > 0)
        let manifest = preview.manifest
        #expect(manifest.formatVersion == 2)
        #expect(manifest.payloads.contains { $0.name == "mail/archive.mbox" && $0.encoding == "mbox" })
        #expect(manifest.payloads.contains { $0.name == "mail/folders.json" })
    }

    @Test("Large mail payloads hash by streaming and verify round-trip")
    func largeMailPayloadStreams() async throws {
        // 8 MB mbox — the writer and reader must hash it in chunks, never
        // load it wholesale (ADR-0077 decision 6).
        let directory = try await makeDirectory("stream")
        let bigBody = Data(repeating: UInt8(ascii: "x"), count: 8 << 20)
        let payload = BackupWriter.MailFile(name: "mail/big.mbox", folderName: "Big") { url in
            try bigBody.write(to: url)
        }
        let url = try await writeBackup(
            to: directory,
            settings: SettingsBackupCodec.export(from: makeStore("source")),
            mailPayloads: [payload]
        )
        let preview = try BackupReader.validate(url: url)
        #expect(preview.mailBytes == Int64(bigBody.count))
        let manifest = preview.manifest
        let expected = SHA256.hash(data: bigBody).map { String(format: "%02x", $0) }.joined()
        #expect(manifest.payloads.first { $0.name == "mail/big.mbox" }?.sha256 == expected)
    }

    @Test("Reader accepts a formatVersion-1 package without mail payloads")
    func readerAcceptsVersion1() async throws {
        let directory = try await makeDirectory("v1")
        let url = try await writeBackup(
            to: directory,
            settings: SettingsBackupCodec.export(from: makeStore("source"))
        )
        try rewriteManifest(at: url) { $0.formatVersion = 1 }
        let preview = try BackupReader.validate(url: url)
        #expect(preview.mailPayloads.isEmpty)
        // And a version newer than supported is still rejected.
        try rewriteManifest(at: url) { $0.formatVersion = 99 }
        #expect(throws: BackupError.unsupportedVersion(99)) {
            try BackupReader.validate(url: url)
        }
    }

    @Test("Mail restore Merge dedupes by Message-ID; Replace recreates")
    func mailRestoreModes() async throws {
        let directory = try await makeDirectory("mailrestore")
        let url = try await writeBackup(
            to: directory,
            settings: SettingsBackupCodec.export(from: makeStore("source")),
            mailPayloads: [mboxFile(body: "kept", messageID: "<dup@example.org>")]
        )
        let preview = try BackupReader.validate(url: url)
        let (backend, root) = try makeLocalBackend("restore")
        defer { try? FileManager.default.removeItem(at: root) }

        let handler: ([LocalMailBackupPayload], LocalMailRestoreMode) async throws
            -> LocalMailRestoreSummary = { payloads, mode in
                await LocalMailBackupImporter.restore(payloads: payloads, into: backend, mode: mode)
            }

        // First restore creates the folder and imports.
        var report = try await BackupRestorer.apply(
            preview: preview, mode: .merge,
            store: makeStore("target1"), signedInEmails: [],
            mailRestoreHandler: handler
        )
        #expect(report.mailRestore?.messagesImported == 1)
        #expect(report.succeededCategories.contains("localMail"))

        // Merge again skips the duplicate Message-ID.
        report = try await BackupRestorer.apply(
            preview: preview, mode: .merge,
            store: makeStore("target2"), signedInEmails: [],
            mailRestoreHandler: handler
        )
        #expect(report.mailRestore?.messagesImported == 0)
        #expect(report.mailRestore?.skippedDuplicates == 1)

        // Replace recreates the folder and reimports.
        report = try await BackupRestorer.apply(
            preview: preview, mode: .replace,
            store: makeStore("target3"), signedInEmails: [],
            mailRestoreHandler: handler
        )
        #expect(report.mailRestore?.messagesImported == 1)

        // includeMail == false leaves the payloads untouched.
        report = try await BackupRestorer.apply(
            preview: preview, mode: .merge,
            store: makeStore("target4"), signedInEmails: [],
            includeMail: false,
            mailRestoreHandler: handler
        )
        #expect(report.mailRestore == nil)
        let remainingFolders = try await backend.folders()
        #expect(remainingFolders.count == 1)
    }
}
