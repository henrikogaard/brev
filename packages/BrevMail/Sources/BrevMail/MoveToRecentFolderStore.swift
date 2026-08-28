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

public struct MoveToRecentFolderStore {
    private static let storageKey = "mail.moveToRecentFolderIDs.v1"
    private static let maxRecentCount = 5

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func recentFolderIDs(for sourceID: MailSourceID) -> [Folder.ID] {
        storage()[Self.key(for: sourceID)] ?? []
    }

    public func record(folderID: Folder.ID, sourceID: MailSourceID) {
        let key = Self.key(for: sourceID)
        var values = storage()
        var recent = values[key] ?? []
        recent.removeAll { $0 == folderID }
        recent.insert(folderID, at: 0)
        values[key] = Array(recent.prefix(Self.maxRecentCount))
        save(values)
    }

    public func sortedMoveCandidates(
        from folders: [Folder],
        currentFolderID: Folder.ID?,
        sourceID: MailSourceID
    ) -> [Folder] {
        Self.sortedMoveCandidates(
            from: folders,
            currentFolderID: currentFolderID,
            recentFolderIDs: recentFolderIDs(for: sourceID)
        )
    }

    public static func sortedMoveCandidates(
        from folders: [Folder],
        currentFolderID: Folder.ID?,
        recentFolderIDs: [Folder.ID]
    ) -> [Folder] {
        let candidates = folders.filter { isValidMoveTarget($0, currentFolderID: currentFolderID) }
        // Failable-merge: a server folder list can contain two folders with the
        // same path (duplicate id), which would trap Dictionary(uniqueKeysWithValues:).
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        var used = Set<Folder.ID>()
        let recent = recentFolderIDs.compactMap { id -> Folder? in
            guard let folder = byID[id], !used.contains(id) else { return nil }
            used.insert(id)
            return folder
        }
        return recent + candidates.filter { !used.contains($0.id) }
    }

    public static func isValidMoveTarget(_ folder: Folder, currentFolderID: Folder.ID?) -> Bool {
        guard folder.id != currentFolderID else { return false }
        switch folder.role {
        case .snoozed, .scheduled, .starred, .allMail:
            return false
        default:
            return true
        }
    }

    private func storage() -> [String: [Folder.ID]] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: [Folder.ID]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func save(_ values: [String: [Folder.ID]]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func key(for sourceID: MailSourceID) -> String {
        "\(sourceID.accountID)|\(sourceID.mailboxID)"
    }
}
