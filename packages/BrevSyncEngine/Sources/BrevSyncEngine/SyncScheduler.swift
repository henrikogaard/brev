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

// MARK: - Priority entry

/// A folder queued for a sync cycle, with the metadata `SyncScheduler`
/// uses to rank it against other pending folders.
public struct SyncQueueEntry: Sendable {
    /// The account that owns this folder.
    public var account: BrevAccount
    /// The folder to sync.
    public var folder: Folder
    /// Priority bucket — lower value means higher urgency.
    public var priority: Priority
    /// Last access time (nil = never visited by the user). Used to rank
    /// within the `.recentlyVisited` bucket.
    public var lastAccessDate: Date?

    /// Sync priority buckets, ordered from highest to lowest urgency
    /// (ADR-0030 §Decision 3).
    public enum Priority: Int, Comparable, Sendable {
        /// The Inbox folder — always synced first.
        case inbox = 0
        /// Folders the user opened in the current or previous session.
        case recentlyVisited = 1
        /// System folders: Sent, Drafts, Junk (in that order by convention).
        case system = 2
        /// All other folders, synced in alphabetical/depth-first order.
        case background = 3

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public init(
        account: BrevAccount,
        folder: Folder,
        priority: Priority,
        lastAccessDate: Date? = nil
    ) {
        self.account = account
        self.folder = folder
        self.priority = priority
        self.lastAccessDate = lastAccessDate
    }
}

// MARK: - Scheduler

/// Maintains a priority queue of folders waiting to be synced and vends
/// them to the background refresh service one at a time.
///
/// `SyncScheduler` is an actor so that `next()` and `enqueue(_:)` are
/// safe to call from any concurrency context, including the background
/// refresh service callback.
///
/// ## Usage
///
/// ```swift
/// // At connect time:
/// await scheduler.enqueue(entries)
///
/// // During background refresh:
/// while let entry = await scheduler.next() {
///     try await syncEngine.syncFolder(entry.folder, for: entry.account, using: operation)
/// }
/// ```
public actor SyncScheduler {
    /// Maximum number of folders processed per background activation
    /// (ADR-0030 §Decision 3). Callers may override this at init time.
    public let maximumFoldersPerActivation: Int

    /// Number of folders vended by `next()` in the current activation window.
    /// Reset to zero by `beginActivation()`.
    private var foldersVendedThisActivation = 0

    /// The ordered queue. Maintained sorted by `(priority, lastAccessDate desc)`
    /// so `next()` is O(1).
    private var queue: [SyncQueueEntry] = []

    /// Set of `(accountID, folderID)` keys currently in the queue, used to
    /// avoid duplicate entries.
    private var queued: Set<String> = []

    // MARK: Init

    /// Creates a scheduler with the given per-activation folder cap.
    ///
    /// - Parameter maximumFoldersPerActivation: How many folders `next()` will
    ///   vend before returning `nil` for the remainder of the activation.
    ///   Defaults to 12, matching the existing background refresh cap in
    ///   `IMAPSMTPBackend`.
    public init(maximumFoldersPerActivation: Int = 12) {
        self.maximumFoldersPerActivation = maximumFoldersPerActivation
    }

    // MARK: Queue management

    /// Adds entries to the priority queue, ignoring duplicates.
    ///
    /// Entries are inserted in sorted position so the queue stays ordered
    /// without a full sort on each insertion.
    ///
    /// - Parameter entries: The folders to enqueue. Already-queued
    ///   `(account, folder)` pairs are silently skipped.
    public func enqueue(_ entries: [SyncQueueEntry]) {
        for entry in entries {
            let key = queueKey(account: entry.account, folder: entry.folder)
            guard queued.insert(key).inserted else { continue }
            let insertionIndex = queue.firstIndex { existing in
                isHigherPriority(entry, than: existing)
            } ?? queue.endIndex
            queue.insert(entry, at: insertionIndex)
        }
    }

    /// Removes all pending entries from the queue and resets the activation counter.
    public func clear() {
        queue.removeAll()
        queued.removeAll()
        foldersVendedThisActivation = 0
    }

    /// Signals the start of a new background activation window, resetting the
    /// per-activation folder counter.
    ///
    /// Call this at the beginning of each background refresh invocation so
    /// `next()` counts correctly within the new window.
    public func beginActivation() {
        foldersVendedThisActivation = 0
    }

    // MARK: Vending

    /// Returns the next highest-priority folder to sync, or `nil` when the
    /// per-activation cap has been reached or the queue is empty.
    ///
    /// The returned entry is removed from the queue. If the sync fails, callers
    /// should re-enqueue it via `enqueue(_:)` for the next activation.
    ///
    /// - Returns: The next `SyncQueueEntry`, or `nil` if the queue is empty or
    ///   the activation cap is exhausted.
    public func next() -> SyncQueueEntry? {
        guard foldersVendedThisActivation < maximumFoldersPerActivation,
              !queue.isEmpty
        else {
            return nil
        }
        let entry = queue.removeFirst()
        queued.remove(queueKey(account: entry.account, folder: entry.folder))
        foldersVendedThisActivation += 1
        return entry
    }

    /// The number of entries currently waiting in the queue.
    public var pendingCount: Int {
        queue.count
    }

    // MARK: Private helpers

    private func queueKey(account: BrevAccount, folder: Folder) -> String {
        "\(account.id)|\(folder.id)"
    }

    /// Returns `true` if `lhs` should be processed before `rhs`.
    ///
    /// Lower priority bucket wins. Within the same bucket, more recently
    /// accessed folders (higher `lastAccessDate`) are preferred because they
    /// are more likely to be visible on screen.
    private func isHigherPriority(_ lhs: SyncQueueEntry, than rhs: SyncQueueEntry) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        switch (lhs.lastAccessDate, rhs.lastAccessDate) {
        case (let lhsDate?, let rhsDate?):
            return lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return false
        }
    }
}
