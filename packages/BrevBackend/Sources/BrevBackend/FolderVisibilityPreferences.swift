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

/// Local, provider-neutral folder presentation state.
///
/// Hidden folders stay synced and available to backend operations; this
/// preference only removes them from mailbox navigation surfaces.
public struct FolderVisibilityPreferences: Codable, Equatable, Sendable {
    public var hiddenFolderIDs: [SourceFolderID]

    public init(hiddenFolderIDs: [SourceFolderID] = []) {
        self.hiddenFolderIDs = Self.orderedUnique(hiddenFolderIDs)
    }

    public static let defaults = FolderVisibilityPreferences()

    private static func orderedUnique(_ folderIDs: [SourceFolderID]) -> [SourceFolderID] {
        var seen: Set<SourceFolderID> = []
        var result: [SourceFolderID] = []
        for folderID in folderIDs where seen.insert(folderID).inserted {
            result.append(folderID)
        }
        return result
    }
}

public enum FolderVisibilityPreferencesPolicy {
    public static func isHidden(
        _ folderID: Folder.ID,
        sourceID: MailSourceID?,
        preferences: FolderVisibilityPreferences
    ) -> Bool {
        guard let sourceID else { return false }
        return Set(preferences.hiddenFolderIDs).contains(SourceFolderID(
            sourceID: sourceID,
            folderID: folderID
        ))
    }

    public static func settingHidden(
        _ isHidden: Bool,
        folderID: Folder.ID,
        sourceID: MailSourceID,
        in preferences: FolderVisibilityPreferences
    ) -> FolderVisibilityPreferences {
        let sourceFolderID = SourceFolderID(sourceID: sourceID, folderID: folderID)
        var hiddenFolderIDs = preferences.hiddenFolderIDs.filter { $0 != sourceFolderID }
        if isHidden {
            hiddenFolderIDs.append(sourceFolderID)
        }
        return FolderVisibilityPreferences(hiddenFolderIDs: hiddenFolderIDs)
    }

    public static func visibleFolders(
        _ folders: [Folder],
        sourceID: MailSourceID?,
        preferences: FolderVisibilityPreferences
    ) -> [Folder] {
        guard let sourceID else { return folders }

        let hiddenSourceFolderIDs = Set(preferences.hiddenFolderIDs)
        var hiddenFolderIDs = Set(folders.compactMap { folder -> Folder.ID? in
            let sourceFolderID = SourceFolderID(sourceID: sourceID, folderID: folder.id)
            return hiddenSourceFolderIDs.contains(sourceFolderID) ? folder.id : nil
        })

        var didHide = true
        while didHide {
            didHide = false
            for folder in folders where !hiddenFolderIDs.contains(folder.id) {
                guard let parentID = folder.parentID,
                      hiddenFolderIDs.contains(parentID)
                else {
                    continue
                }
                hiddenFolderIDs.insert(folder.id)
                didHide = true
            }
        }

        return folders.filter { !hiddenFolderIDs.contains($0.id) }
    }

    public static func removingAccount(
        _ accountID: BrevAccount.ID,
        from preferences: FolderVisibilityPreferences
    ) -> FolderVisibilityPreferences {
        FolderVisibilityPreferences(
            hiddenFolderIDs: preferences.hiddenFolderIDs.filter { $0.sourceID.accountID != accountID }
        )
    }
}

public enum FolderVisibilityPreferencesStorage {
    public static let storageKey = "folder.visibilityPreferences"

    public static func load(from defaults: UserDefaults = .standard) -> FolderVisibilityPreferences {
        guard let data = defaults.data(forKey: storageKey) else {
            return .defaults
        }
        return decode(data) ?? .defaults
    }

    public static func save(
        _ preferences: FolderVisibilityPreferences,
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
        let next = FolderVisibilityPreferencesPolicy.removingAccount(
            accountID,
            from: load(from: defaults)
        )
        save(next, to: defaults)
    }

    public static func decode(_ data: Data) -> FolderVisibilityPreferences? {
        try? JSONDecoder().decode(FolderVisibilityPreferences.self, from: data)
    }

    public static func encode(_ preferences: FolderVisibilityPreferences) -> Data? {
        try? JSONEncoder().encode(preferences)
    }
}
