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

@Suite("AccountMailboxSyncSettings")
struct AccountMailboxSyncSettingsTests {
    @Test("defaults use all-folders sync with 90-day retention semantics")
    func defaults() throws {
        let defaults = try Self.makeDefaults()
        let settings = AccountMailboxSyncSettings.load(from: defaults)

        #expect(settings.roleMappingsByAccountID.isEmpty)
        #expect(settings.folderSyncScope == .allFolders)
        #expect(settings.includeSharedFolders)
        #expect(settings.includeArchiveFolders)
        #expect(settings.offlineRetentionPolicy == .keep90Days)
        #expect(settings.offlineRetentionPolicy.description.contains("90"))
    }

    @Test("retention policies map to the expected day windows and body semantics")
    func retentionDayMapping() {
        #expect(OfflineRetentionPolicy.keep7Days.retentionDays == 7)
        #expect(OfflineRetentionPolicy.keep14Days.retentionDays == 14)
        #expect(OfflineRetentionPolicy.keep30Days.retentionDays == 30)
        #expect(OfflineRetentionPolicy.keep90Days.retentionDays == 90)
        #expect(OfflineRetentionPolicy.keep6Months.retentionDays == 180)
        #expect(OfflineRetentionPolicy.keep1Year.retentionDays == 365)
        #expect(OfflineRetentionPolicy.keepAll.retentionDays == nil)
        #expect(OfflineRetentionPolicy.headersOnly.retentionDays == nil)

        // Only headers-only drops bodies entirely.
        for policy in OfflineRetentionPolicy.allCases {
            #expect(policy.keepsBodies == (policy != .headersOnly))
        }

        // The original four cases keep their persisted raw values so old
        // preferences and exported settings still decode.
        #expect(OfflineRetentionPolicy.keepAll.rawValue == "keepAll")
        #expect(OfflineRetentionPolicy.keep90Days.rawValue == "keep90Days")
        #expect(OfflineRetentionPolicy.keep30Days.rawValue == "keep30Days")
        #expect(OfflineRetentionPolicy.headersOnly.rawValue == "headersOnly")
    }

    @Test("saving and loading preserves mappings and sync policy")
    func roundTrip() throws {
        let defaults = try Self.makeDefaults()
        var settings = AccountMailboxSyncSettings.defaults
        settings.folderSyncScope = .subscribedOnly
        settings.includeSharedFolders = false
        settings.includeArchiveFolders = false
        settings.offlineRetentionPolicy = .headersOnly
        settings.setRoleMapping(
            AccountMailboxRoleMapping(
                accountID: "acc-1",
                draftsFolderID: "drafts-a",
                sentFolderID: "sent-a",
                junkFolderID: "junk-a",
                trashFolderID: "trash-a",
                archiveFolderID: "archive-a"
            )
        )

        settings.save(to: defaults)
        let restored = AccountMailboxSyncSettings.load(from: defaults)

        #expect(restored.folderSyncScope == .subscribedOnly)
        #expect(restored.includeSharedFolders == false)
        #expect(restored.includeArchiveFolders == false)
        #expect(restored.offlineRetentionPolicy == .headersOnly)
        #expect(restored.roleMappingsByAccountID["acc-1"]?.sentFolderID == "sent-a")
    }

    @Test("corrupt persisted values fall back to defaults")
    func corruptDataFallback() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("not-json".data(using: .utf8), forKey: AccountMailboxSyncSettings.Key.roleMappings)
        defaults.set("invalid", forKey: AccountMailboxSyncSettings.Key.folderSyncScope)
        defaults.set("invalid", forKey: AccountMailboxSyncSettings.Key.offlineRetentionPolicy)

        let restored = AccountMailboxSyncSettings.load(from: defaults)

        #expect(restored.roleMappingsByAccountID.isEmpty)
        #expect(restored.folderSyncScope == .allFolders)
        #expect(restored.offlineRetentionPolicy == .keep90Days)
    }

    @Test("role mapping helper returns defaults and supports removal")
    func roleMappingHelpers() throws {
        var settings = AccountMailboxSyncSettings.defaults
        let fallback = settings.roleMapping(for: "acc-x")
        #expect(fallback.accountID == "acc-x")
        #expect(fallback.archiveFolderID == nil)

        settings.setRoleMapping(
            AccountMailboxRoleMapping(accountID: "acc-x", archiveFolderID: "archive-x")
        )
        #expect(settings.roleMapping(for: "acc-x").archiveFolderID == "archive-x")

        settings.removeRoleMapping(accountID: "acc-x")
        #expect(settings.roleMapping(for: "acc-x").archiveFolderID == nil)
    }

    @Test("folder override helpers prune default retention and auto-sync values")
    func folderOverrideHelpersPruneDefaults() {
        var settings = AccountMailboxSyncSettings.defaults

        settings.setRetentionPolicy(.headersOnly, forFolderID: "archive")
        #expect(settings.policy(for: "archive") == .headersOnly)
        #expect(settings.folderOverrides["archive"]?.retentionPolicy == .headersOnly)

        settings.setRetentionPolicy(nil, forFolderID: "archive")
        #expect(settings.policy(for: "archive") == settings.offlineRetentionPolicy)
        #expect(settings.folderOverrides["archive"] == nil)

        settings.setRetentionPolicy(.keep7Days, forFolderID: "archive")
        #expect(settings.folderOverrides["archive"] == FolderSyncOverride(retentionPolicy: .keep7Days))
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suite = "AccountMailboxSyncSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
