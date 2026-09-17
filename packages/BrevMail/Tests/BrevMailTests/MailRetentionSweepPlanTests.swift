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
@testable import BrevMail
import BrevSettings
import Foundation
import Testing

@Suite("MailRetentionSweepPlan")
struct MailRetentionSweepPlanTests {
    @Test("retention sweeps honor the selected source's override for duplicate folder IDs")
    func sourceOverrides() {
        let work = MailSourceID(accountID: "account", mailboxID: "work")
        let personal = MailSourceID(accountID: "account", mailboxID: "personal")
        var settings = AccountMailboxSyncSettings.defaults
        settings.setRetentionPolicy(.headersOnly, forFolderID: "INBOX", sourceID: work)
        let folders = [Folder(id: "INBOX", name: "Inbox", role: .inbox)]
        let workTargets = MailRetentionSweepPlan.targets(sourceSections: [], fallbackSourceID: work,
                                                         fallbackFolders: folders, settings: settings)
        let personalTargets = MailRetentionSweepPlan.targets(sourceSections: [], fallbackSourceID: personal,
                                                             fallbackFolders: folders, settings: settings)
        #expect(workTargets.first?.keepsBodies == false)
        #expect(personalTargets.first?.keepsBodies == true)
        #expect(personalTargets.first?.retentionDays == 90)
    }

    @Test("retention sweep waits while sync health reports indexing")
    func retentionSweepWaitsWhileSyncHealthReportsIndexing() {
        let sourceID = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let indexing = AccountSyncHealth(
            sourceID: sourceID,
            state: .indexing,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 42),
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )
        let rebuilding = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: nil,
            indexStatus: .rebuilding(progress: 0.5),
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )
        let idle = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 42),
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )

        #expect(!MailRetentionSweepPlan.shouldApplyRetention(syncHealth: indexing))
        #expect(!MailRetentionSweepPlan.shouldApplyRetention(syncHealth: rebuilding))
        #expect(MailRetentionSweepPlan.shouldApplyRetention(syncHealth: idle))
        #expect(MailRetentionSweepPlan.shouldApplyRetention(syncHealth: nil))
    }

    @Test("mail root keeps injected settings store for retention sweeps")
    func mailRootKeepsInjectedSettingsStoreForRetentionSweeps() throws {
        let defaultsName = "brev-root-retention-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = SettingsPersistenceStore(defaults: defaults)
        let view = BrevMailRootView(backend: MockBackend(), settingsStore: store)

        let reflectedStore = Mirror(reflecting: view).children.first {
            $0.label == "settingsStore"
        }?.value as? SettingsPersistenceStore

        #expect(reflectedStore == store)
    }

    @Test("fallback folders are pruned when source sections are not loaded")
    func fallbackFoldersArePrunedWhenSourceSectionsAreNotLoaded() {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let archive = Folder(id: "Archive", name: "Archive", role: .archive)
        let fallbackSourceID = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let settings = AccountMailboxSyncSettings(
            roleMappingsByAccountID: [:],
            folderSyncScope: .allFolders,
            includeSharedFolders: true,
            includeArchiveFolders: true,
            offlineRetentionPolicy: .keep30Days,
            folderOverrides: [
                "Archive": FolderSyncOverride(retentionPolicy: .headersOnly)
            ]
        )

        let targets = MailRetentionSweepPlan.targets(
            sourceSections: [],
            fallbackSourceID: fallbackSourceID,
            fallbackFolders: [inbox, archive],
            settings: settings
        )

        #expect(targets == [
            MailRetentionSweepTarget(
                sourceID: fallbackSourceID,
                accountID: "account-a",
                folderID: "INBOX",
                retentionDays: 30,
                keepsBodies: true
            ),
            MailRetentionSweepTarget(
                sourceID: fallbackSourceID,
                accountID: "account-a",
                folderID: "Archive",
                retentionDays: nil,
                keepsBodies: false
            )
        ])
    }

    @Test("source sections take priority over fallback folders")
    func sourceSectionsTakePriorityOverFallbackFolders() {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let fallbackFolder = Folder(id: "Fallback", name: "Fallback", role: .custom)
        let section = Self.section(accountID: "account-a", mailboxID: "mailbox-a", folders: [inbox])

        let targets = MailRetentionSweepPlan.targets(
            sourceSections: [section],
            fallbackSourceID: MailSourceID(accountID: "fallback-account", mailboxID: "fallback-mailbox"),
            fallbackFolders: [fallbackFolder],
            settings: .defaults
        )

        #expect(targets == [
            MailRetentionSweepTarget(
                sourceID: MailSourceID(accountID: "account-a", mailboxID: "mailbox-a"),
                accountID: "account-a",
                folderID: "INBOX",
                retentionDays: 90,
                keepsBodies: true
            )
        ])
    }

    @Test("fallback folders are skipped without a real source")
    func fallbackFoldersAreSkippedWithoutRealSource() {
        let targets = MailRetentionSweepPlan.targets(
            sourceSections: [],
            fallbackSourceID: nil,
            fallbackFolders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox)
            ],
            settings: .defaults
        )

        #expect(targets.isEmpty)
    }

    @Test("duplicate account folder targets are emitted once")
    func duplicateAccountFolderTargetsAreEmittedOnce() {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let section = Self.section(
            accountID: "account-a",
            mailboxID: "mailbox-a",
            folders: [inbox, inbox]
        )

        let targets = MailRetentionSweepPlan.targets(
            sourceSections: [section],
            fallbackSourceID: nil,
            fallbackFolders: [],
            settings: .defaults
        )

        #expect(targets.count == 1)
        #expect(targets.first?.folderID == "INBOX")
    }

    @Test("duplicate folders in different mailboxes are retained separately")
    func duplicateFoldersInDifferentMailboxesAreRetainedSeparately() {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let primary = Self.section(
            accountID: "account-a",
            mailboxID: "primary",
            folders: [inbox]
        )
        let shared = Self.section(
            accountID: "account-a",
            mailboxID: "shared",
            folders: [inbox]
        )

        let targets = MailRetentionSweepPlan.targets(
            sourceSections: [primary, shared],
            fallbackSourceID: nil,
            fallbackFolders: [],
            settings: .defaults
        )

        #expect(targets.map(\.sourceID) == [
            MailSourceID(accountID: "account-a", mailboxID: "primary"),
            MailSourceID(accountID: "account-a", mailboxID: "shared")
        ])
        #expect(targets.allSatisfy { $0.folderID == "INBOX" })
    }

    private static func section(
        accountID: String,
        mailboxID: String,
        folders: [Folder]
    ) -> MailSourceSection {
        MailSourceSection(
            id: MailSourceID(accountID: accountID, mailboxID: mailboxID),
            account: BrevAccount(
                id: accountID,
                displayName: accountID,
                emailAddress: "\(accountID)@example.test"
            ),
            mailbox: Mailbox(
                id: mailboxID,
                email: "\(mailboxID)@example.test",
                displayName: mailboxID,
                isPrimary: true
            ),
            folders: folders
        )
    }
}
