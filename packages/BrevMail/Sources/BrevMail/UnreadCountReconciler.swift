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

/// Reconciles a `Folder.unreadCount` after a bulk mutation (mark read,
/// mark unread, bulk move) so the sidebar stays in sync without waiting
/// for the next folder-list refresh.
///
/// Counts are optimistic: the reconciler trusts that the user-visible
/// mutation succeeded (we just awaited the backend call) and adjusts the
/// provided folder in place. Negative deltas are clamped to zero so a
/// drift between the optimistic count and the server's truth never
/// produces a negative badge.
struct UnreadCountReconciler: Sendable {
    /// Returns a copy of `folder` with `unreadCount` adjusted by `delta`,
    /// clamped to `>= 0`.
    func adjust(folderID: String, delta: Int, in folders: [Folder]) -> Folder? {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return nil }
        return adjust(folder: folder, delta: delta)
    }

    /// Returns a copy of `folder` with `unreadCount` adjusted by `delta`,
    /// clamped to `>= 0`.
    func adjust(folder: Folder, delta: Int) -> Folder {
        let newCount = max(0, folder.unreadCount + delta)
        guard newCount != folder.unreadCount else { return folder }
        return Folder(
            id: folder.id,
            name: folder.name,
            role: folder.role,
            parentID: folder.parentID,
            unreadCount: newCount,
            totalCount: folder.totalCount
        )
    }

    /// Returns a copy of `folders` with the matching folder's
    /// `unreadCount` adjusted by `delta` (clamped to `>= 0`). Folders
    /// that don't match the id are returned unchanged.
    func apply(folderID: String, delta: Int, to folders: [Folder]) -> [Folder] {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return folders }
        let updated = adjust(folder: folders[index], delta: delta)
        guard updated.unreadCount != folders[index].unreadCount else { return folders }
        var result = folders
        result[index] = updated
        return result
    }
}
