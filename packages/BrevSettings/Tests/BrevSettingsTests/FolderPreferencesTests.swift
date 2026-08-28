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

@Suite("FolderPreferences")
struct FolderPreferencesTests {
    @Test("defaults show common folders")
    func defaultsShowCommonFolders() throws {
        let defaults = try Self.makeDefaults()
        let prefs = FolderPreferences.load(from: defaults)

        #expect(prefs.showStarred == true)
        #expect(prefs.showSnoozed == true)
        #expect(prefs.showScheduled == true)
        #expect(prefs.showAllMail == false)
        #expect(prefs.showSpam == true)
        #expect(prefs.showTrash == true)
        #expect(prefs.showArchive == true)
    }

    @Test("saving and loading preserves every folder preference")
    func savingAndLoadingPreserves() throws {
        let defaults = try Self.makeDefaults()
        var prefs = FolderPreferences.defaults
        prefs.showAllMail = true
        prefs.showSpam = false

        prefs.save(to: defaults)
        let restored = FolderPreferences.load(from: defaults)

        #expect(restored.showAllMail == true)
        #expect(restored.showSpam == false)
    }

    @Test("unwritten folder keys fall back to defaults")
    func unwrittenKeysFallBack() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(true, forKey: FolderPreferences.Key.showAllMail)

        let prefs = FolderPreferences.load(from: defaults)
        #expect(prefs.showAllMail == true)
        #expect(prefs.showArchive == FolderPreferences.defaults.showArchive)
    }

    @Test("settings store persists hidden folder preferences")
    func settingsStorePersistsHiddenFolderPreferences() throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "work")
        let preferences = FolderVisibilityPreferences(hiddenFolderIDs: [
            SourceFolderID(sourceID: sourceID, folderID: "archive")
        ])

        store.save(preferences)

        #expect(store.folderVisibilityPreferences() == preferences)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suite = "FolderPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
