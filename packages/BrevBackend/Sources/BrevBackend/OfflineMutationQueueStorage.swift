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

/// Shared storage-key conventions and housekeeping helpers for
/// account-scoped offline mutation queues and replay conflict summaries.
public enum OfflineMutationQueueStorage {
    public static func storageKey(accountID: String) -> String {
        let safeAccountID = accountID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "backend.offlineMutationQueue.\(safeAccountID).v1"
    }

    public static func conflictStorageKey(accountID: String) -> String {
        let safeAccountID = accountID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "backend.offlineMutationConflicts.\(safeAccountID).v1"
    }

    public static func queue(
        accountID: String,
        defaults: UserDefaults = .standard
    ) -> UserDefaultsMutationQueue {
        UserDefaultsMutationQueue(
            defaults: defaults,
            storageKey: storageKey(accountID: accountID)
        )
    }

    public static func conflictStore(
        accountID: String,
        defaults: UserDefaults = .standard
    ) -> UserDefaultsMutationConflictStore {
        UserDefaultsMutationConflictStore(
            defaults: defaults,
            storageKey: conflictStorageKey(accountID: accountID)
        )
    }

    public static func clearPendingMutations(
        for accountID: String,
        defaults: UserDefaults = .standard
    ) async {
        let queue = queue(accountID: accountID, defaults: defaults)
        try? await queue.removeAll()
        let conflictStore = conflictStore(accountID: accountID, defaults: defaults)
        try? await conflictStore.removeAll()
    }
}
