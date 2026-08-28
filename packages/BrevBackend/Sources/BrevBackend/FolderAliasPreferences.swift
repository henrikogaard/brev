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

import Foundation

/// Local, provider-neutral folder display names.
///
/// Aliases are Brev presentation state only. They never mutate provider
/// folders and never replace `Folder.name` as the backend truth.
public struct FolderAliasPreference: Codable, Equatable, Identifiable, Sendable {
    public let folderID: SourceFolderID
    public let name: String

    public init(folderID: SourceFolderID, name: String) {
        self.folderID = folderID
        self.name = name
    }

    public var id: SourceFolderID { folderID }
}

public struct FolderAliasPreferences: Codable, Equatable, Sendable {
    public var aliases: [FolderAliasPreference]

    public init(aliases: [FolderAliasPreference] = []) {
        self.aliases = Self.normalized(aliases)
    }

    public static let defaults = FolderAliasPreferences()

    private static func normalized(_ aliases: [FolderAliasPreference]) -> [FolderAliasPreference] {
        var indexesByFolderID: [SourceFolderID: Int] = [:]
        var result: [FolderAliasPreference] = []
        for alias in aliases {
            let name = alias.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let normalized = FolderAliasPreference(folderID: alias.folderID, name: name)
            if let index = indexesByFolderID[alias.folderID] {
                result[index] = normalized
            } else {
                indexesByFolderID[alias.folderID] = result.count
                result.append(normalized)
            }
        }
        return result
    }
}

public enum FolderAliasPreferencesPolicy {
    public static func alias(
        for folderID: Folder.ID,
        sourceID: MailSourceID?,
        preferences: FolderAliasPreferences
    ) -> String? {
        guard let sourceID else { return nil }
        let sourceFolderID = SourceFolderID(sourceID: sourceID, folderID: folderID)
        return preferences.aliases.first { $0.folderID == sourceFolderID }?.name
    }

    public static func settingAlias(
        _ alias: String?,
        folderID: Folder.ID,
        sourceID: MailSourceID,
        in preferences: FolderAliasPreferences
    ) -> FolderAliasPreferences {
        let sourceFolderID = SourceFolderID(sourceID: sourceID, folderID: folderID)
        let trimmedAlias = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var aliases = preferences.aliases.filter { $0.folderID != sourceFolderID }
        if !trimmedAlias.isEmpty {
            aliases.append(FolderAliasPreference(folderID: sourceFolderID, name: trimmedAlias))
        }
        return FolderAliasPreferences(aliases: aliases)
    }

    public static func displayName(
        for folder: Folder,
        sourceID: MailSourceID?,
        preferences: FolderAliasPreferences
    ) -> String {
        if let alias = alias(for: folder.id, sourceID: sourceID, preferences: preferences) {
            return alias
        }
        if let standardName = standardDisplayName(for: folder.role) {
            return standardName
        }
        return folder.name
    }

    public static func standardDisplayName(for role: FolderRole) -> String? {
        switch role {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .trash: return "Trash"
        case .spam: return "Spam"
        case .archive: return "Archive"
        case .snoozed: return "Snoozed"
        case .scheduled: return "Scheduled"
        case .starred: return "Flagged"
        case .allMail: return "All Mail"
        case .custom: return nil
        }
    }

    public static func removingAccount(
        _ accountID: BrevAccount.ID,
        from preferences: FolderAliasPreferences
    ) -> FolderAliasPreferences {
        FolderAliasPreferences(
            aliases: preferences.aliases.filter { $0.folderID.sourceID.accountID != accountID }
        )
    }
}

public enum FolderAliasPreferencesStorage {
    public static let storageKey = "folder.aliasPreferences"

    public static func load(from defaults: UserDefaults = .standard) -> FolderAliasPreferences {
        guard let data = defaults.data(forKey: storageKey) else {
            return .defaults
        }
        return decode(data) ?? .defaults
    }

    public static func save(
        _ preferences: FolderAliasPreferences,
        to defaults: UserDefaults = .standard
    ) {
        guard let data = encode(preferences) else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    public static func removeAccount(
        _ accountID: BrevAccount.ID,
        from defaults: UserDefaults = .standard
    ) {
        let next = FolderAliasPreferencesPolicy.removingAccount(
            accountID,
            from: load(from: defaults)
        )
        save(next, to: defaults)
    }

    public static func decode(_ data: Data) -> FolderAliasPreferences? {
        try? JSONDecoder().decode(FolderAliasPreferences.self, from: data)
    }

    public static func encode(_ preferences: FolderAliasPreferences) -> Data? {
        try? JSONEncoder().encode(preferences)
    }
}
