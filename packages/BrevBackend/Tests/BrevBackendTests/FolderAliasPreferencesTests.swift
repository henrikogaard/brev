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

@Suite("FolderAliasPreferences")
struct FolderAliasPreferencesTests {
    private let work = MailSourceID(accountID: "acct-1", mailboxID: "work")
    private let personal = MailSourceID(accountID: "acct-1", mailboxID: "personal")

    @Test("aliases are trimmed and scoped to the mailbox source")
    func aliasesAreTrimmedAndScopedToMailboxSource() {
        let inbox = Folder(id: "inbox", name: "INBOX", role: .inbox)

        let preferences = FolderAliasPreferencesPolicy.settingAlias(
            "  Inbox Zero  ",
            folderID: inbox.id,
            sourceID: personal,
            in: .defaults
        )

        #expect(FolderAliasPreferencesPolicy.alias(
            for: inbox.id,
            sourceID: personal,
            preferences: preferences
        ) == "Inbox Zero")
        #expect(FolderAliasPreferencesPolicy.alias(
            for: inbox.id,
            sourceID: work,
            preferences: preferences
        ) == nil)
        #expect(FolderAliasPreferencesPolicy.displayName(
            for: inbox,
            sourceID: personal,
            preferences: preferences
        ) == "Inbox Zero")
        #expect(FolderAliasPreferencesPolicy.displayName(
            for: inbox,
            sourceID: work,
            preferences: preferences
        ) == "Inbox")
    }

    @Test("blank aliases clear the local override")
    func blankAliasesClearTheLocalOverride() {
        let inbox = Folder(id: "inbox", name: "INBOX", role: .inbox)
        let aliased = FolderAliasPreferencesPolicy.settingAlias(
            "Home",
            folderID: inbox.id,
            sourceID: personal,
            in: .defaults
        )

        let cleared = FolderAliasPreferencesPolicy.settingAlias(
            " ",
            folderID: inbox.id,
            sourceID: personal,
            in: aliased
        )

        #expect(FolderAliasPreferencesPolicy.alias(
            for: inbox.id,
            sourceID: personal,
            preferences: cleared
        ) == nil)
        #expect(FolderAliasPreferencesPolicy.displayName(
            for: inbox,
            sourceID: personal,
            preferences: cleared
        ) == "Inbox")
    }

    @Test("custom folders fall back to the provider name")
    func customFoldersFallBackToProviderName() {
        let receipts = Folder(id: "receipts", name: "RECEIPTS", role: .custom)

        #expect(FolderAliasPreferencesPolicy.displayName(
            for: receipts,
            sourceID: personal,
            preferences: .defaults
        ) == "RECEIPTS")
    }

    @Test("storage round trips aliases")
    func storageRoundTripsAliases() throws {
        let defaults = try Self.makeDefaults()
        let preferences = FolderAliasPreferences(aliases: [
            FolderAliasPreference(
                folderID: SourceFolderID(sourceID: personal, folderID: "inbox"),
                name: "Inbox Zero"
            )
        ])

        FolderAliasPreferencesStorage.save(preferences, to: defaults)

        #expect(FolderAliasPreferencesStorage.load(from: defaults) == preferences)
    }

    @Test("storage removes aliases for signed-out accounts")
    func storageRemovesAliasesForSignedOutAccounts() throws {
        let defaults = try Self.makeDefaults()
        let other = MailSourceID(accountID: "acct-2", mailboxID: "shared")
        let preferences = FolderAliasPreferences(aliases: [
            FolderAliasPreference(
                folderID: SourceFolderID(sourceID: personal, folderID: "inbox"),
                name: "Home"
            ),
            FolderAliasPreference(
                folderID: SourceFolderID(sourceID: other, folderID: "inbox"),
                name: "Shared"
            )
        ])

        FolderAliasPreferencesStorage.save(preferences, to: defaults)
        FolderAliasPreferencesStorage.removeAccount("acct-1", from: defaults)

        #expect(FolderAliasPreferencesStorage.load(from: defaults) == FolderAliasPreferences(aliases: [
            FolderAliasPreference(
                folderID: SourceFolderID(sourceID: other, folderID: "inbox"),
                name: "Shared"
            )
        ]))
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "FolderAliasPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("standard folder names carry Norwegian translations")
    func standardFolderNamesCarryNorwegianTranslations() throws {
        let strings = try Self.loadBackendCatalogStrings()
        let roles: [(FolderRole, String)] = [
            (.inbox, "Inbox"),
            (.sent, "Sent"),
            (.drafts, "Drafts"),
            (.trash, "Trash"),
            (.spam, "Spam"),
            (.archive, "Archive"),
            (.snoozed, "Snoozed"),
            (.scheduled, "Scheduled"),
            (.starred, "Flagged"),
            (.allMail, "All Mail")
        ]

        for (role, name) in roles {
            #expect(FolderAliasPreferencesPolicy.standardDisplayName(for: role) != nil)

            let entry = strings[name] as? [String: Any]
            let localization = (entry?["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            let unit = localization?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String

            #expect(unit?["state"] as? String == "translated", "missing nb translation for \(name)")
            #expect(value?.isEmpty == false && value != name, "\(name) still falls back to English")
        }
    }

    private static func loadBackendCatalogStrings() throws -> [String: Any] {
        // Resolve from the source file so the check works from any runner
        // working directory, with the repository root as a fallback.
        let relativePath = "packages/BrevBackend/Sources/BrevBackend/Resources/Localizable.xcstrings"
        var candidates: [URL] = []
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 7 {
            candidates.append(directory.appendingPathComponent(relativePath))
            directory.deleteLastPathComponent()
        }
        directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0 ..< 7 {
            candidates.append(directory.appendingPathComponent(relativePath))
            directory.deleteLastPathComponent()
        }

        guard let catalogURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CatalogLookupError.notFound
        }
        let data = try Data(contentsOf: catalogURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(root?["strings"] as? [String: Any])
    }

    private enum CatalogLookupError: Error {
        case notFound
    }
}
