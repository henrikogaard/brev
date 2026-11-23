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

import BrevAI
import BrevBackend
@testable import BrevSettings
import Foundation
import Testing

@Suite("SettingsPersistenceStore")
struct SettingsPersistenceStoreTests {
    @Test("store centralizes typed settings reads and writes")
    func storeCentralizesTypedSettingsReadsAndWrites() throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let compose = ComposeSettings(
            messageFormat: .plainText,
            attachmentReminderEnabled: false,
            externalRecipientWarningEnabled: false,
            quotePlacement: .aboveReply,
            undoSendDelay: .tenSeconds,
            textCheckingEnabled: false
        )
        let browser = BrowserSettings(preferredBrowser: .brave)
        let ai = AIWriterSettings(isEnabled: true, consentGiven: true)
        let updates = UpdateSettings(cadence: .manual)
        let securityKeyMaterial = SecurityKeyMaterialSettings(
            records: [
                .init(
                    id: "smime-1",
                    family: .smime,
                    label: "Local certificate",
                    emailAddress: "a@example.com",
                    fingerprint: "AA11",
                    algorithm: "Ed25519",
                    canSign: true,
                    canEncrypt: true,
                    hasPrivateMaterial: true,
                    trust: .trusted,
                    importedAt: Date(timeIntervalSince1970: 1_718_000_000)
                )
            ],
            importExport: .init(
                smimeExportFormat: .pem,
                includePrivateMaterialInExport: false,
                allowReplacingExistingMaterialOnImport: true
            )
        )
        let accountSync = AccountMailboxSyncSettings(
            roleMappingsByAccountID: [
                "acc-1": AccountMailboxRoleMapping(
                    accountID: "acc-1",
                    draftsFolderID: "drafts"
                )
            ],
            folderSyncScope: .subscribedOnly,
            includeSharedFolders: false,
            includeArchiveFolders: true,
            offlineRetentionPolicy: .keep30Days
        )
        let localRules = LocalRulesSettings(
            rules: [
                ServerRule(
                    id: "rule-1",
                    name: "Archive newsletters",
                    isEnabled: true,
                    conditions: [.subjectContains("newsletter")],
                    actions: [.archive]
                )
            ],
            isAutomaticExecutionEnabled: true
        )

        store.save(compose)
        store.save(browser)
        store.save(ai)
        store.save(updates)
        store.save(securityKeyMaterial)
        store.save(accountSync)
        store.save(localRules)

        #expect(store.composeSettings() == compose)
        #expect(store.browserSettings() == browser)
        #expect(store.aiWriterSettings() == ai)
        #expect(store.updateSettings() == updates)
        #expect(store.securityKeyMaterialSettings() == securityKeyMaterial)
        #expect(store.accountMailboxSyncSettings() == accountSync)
        #expect(store.localRulesSettings() == localRules)
    }

    @Test("standard store is the default shared persistence boundary")
    func standardStoreIsTheDefaultSharedPersistenceBoundary() {
        #expect(SettingsPersistenceStore.standard == SettingsPersistenceStore(defaults: .standard))
    }

    @Test("opaque data stays in the injected defaults suite")
    func opaqueDataUsesInjectedDefaults() throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let key = "settings-store-data-\(UUID().uuidString)"
        let value = Data([1, 2, 3])

        store.saveData(value, forKey: key)

        #expect(store.data(forKey: key) == value)
        #expect(UserDefaults.standard.data(forKey: key) == nil)

        store.saveData(nil, forKey: key)
        #expect(store.data(forKey: key) == nil)
    }

    @Test("account cleanup removes workflow snoozes only from its injected suite")
    func accountCleanupRemovesInjectedWorkflowState() throws {
        let defaults = try Self.makeDefaults()
        let otherDefaults = try Self.makeDefaults()
        let first = LocalMessageSnooze(
            messageID: .init(sourceID: .init(accountID: "account-a", mailboxID: "personal"), messageID: "a"),
            wakeAt: Date(timeIntervalSince1970: 20000),
            createdAt: Date(timeIntervalSince1970: 10000),
            conversationMetadata: .init(rfcIdentifiers: ["a@example.org"])
        )
        let second = LocalMessageSnooze(
            messageID: .init(sourceID: .init(accountID: "account-b", mailboxID: "personal"), messageID: "b"),
            wakeAt: Date(timeIntervalSince1970: 20000),
            createdAt: Date(timeIntervalSince1970: 10000),
            conversationMetadata: .init(rfcIdentifiers: ["b@example.org"])
        )
        let state = LocalMessageWorkflowState(snoozes: [first, second])
        LocalMessageWorkflowStateStorage.save(state, to: defaults)
        LocalMessageWorkflowStateStorage.save(state, to: otherDefaults)

        SettingsPersistenceStore(defaults: defaults).removeAccountScopedState(accountID: "account-a")

        #expect(LocalMessageWorkflowStateStorage.load(from: defaults).snoozes == [second])
        #expect(LocalMessageWorkflowStateStorage.load(from: otherDefaults) == state)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsPersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
