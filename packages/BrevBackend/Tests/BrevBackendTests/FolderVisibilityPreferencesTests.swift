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
import Foundation
import Testing

@Suite("FolderVisibilityPreferences")
struct FolderVisibilityPreferencesTests {
    private let work = MailSourceID(accountID: "acct-1", mailboxID: "work")
    private let personal = MailSourceID(accountID: "acct-1", mailboxID: "personal")

    @Test("hidden folders are scoped to the mailbox source")
    func hiddenFoldersAreScopedToMailboxSource() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom, parentID: archive.id)
        let personalArchive = SourceFolderID(sourceID: personal, folderID: archive.id)
        let preferences = FolderVisibilityPreferences(hiddenFolderIDs: [personalArchive])

        #expect(FolderVisibilityPreferencesPolicy.visibleFolders(
            [inbox, archive, receipts],
            sourceID: work,
            preferences: preferences
        ).map(\.id) == ["inbox", "archive", "receipts"])

        #expect(FolderVisibilityPreferencesPolicy.visibleFolders(
            [inbox, archive, receipts],
            sourceID: personal,
            preferences: preferences
        ).map(\.id) == ["inbox"])
    }

    @Test("storage removes hidden folders for signed-out accounts")
    func storageRemovesHiddenFoldersForSignedOutAccounts() throws {
        let defaults = try Self.makeDefaults()
        let other = MailSourceID(accountID: "acct-2", mailboxID: "shared")
        let preferences = FolderVisibilityPreferences(hiddenFolderIDs: [
            SourceFolderID(sourceID: work, folderID: "archive"),
            SourceFolderID(sourceID: other, folderID: "archive")
        ])

        FolderVisibilityPreferencesStorage.save(preferences, to: defaults)
        FolderVisibilityPreferencesStorage.removeAccount("acct-1", from: defaults)

        #expect(FolderVisibilityPreferencesStorage.load(from: defaults) == FolderVisibilityPreferences(
            hiddenFolderIDs: [SourceFolderID(sourceID: other, folderID: "archive")]
        ))
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "FolderVisibilityPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
