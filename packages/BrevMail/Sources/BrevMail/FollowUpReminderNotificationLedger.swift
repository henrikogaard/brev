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

struct FollowUpReminderNotificationLedger: Codable, Equatable {
    enum State: String, Codable {
        case scheduled
        case delivered
        case denied
        case failed
    }

    struct Entry: Codable, Equatable {
        var dueAt: Date
        var state: State
        var nextRetryAt: Date?
    }

    static let userDefaultsKey = "notifications.followUpReminderLedger.v1"

    private(set) var entries: [String: Entry] = [:]

    mutating func shouldSchedule(
        identifier: String,
        dueAt: Date,
        now: Date,
        pendingIDs: Set<String>,
        deliveredIDs: Set<String>,
        authorizationAvailable: Bool
    ) -> Bool {
        if let entry = entries[identifier], entry.dueAt != dueAt {
            entries[identifier] = nil
        }
        if deliveredIDs.contains(identifier) {
            entries[identifier] = Entry(dueAt: dueAt, state: .delivered)
            return false
        }
        if pendingIDs.contains(identifier) {
            entries[identifier] = Entry(dueAt: dueAt, state: .scheduled)
            return false
        }
        guard authorizationAvailable else {
            entries[identifier] = Entry(dueAt: dueAt, state: .denied)
            return false
        }
        guard let entry = entries[identifier] else { return true }
        switch entry.state {
        case .delivered:
            return false
        case .failed:
            return entry.nextRetryAt.map { now >= $0 } ?? true
        case .denied:
            return true
        case .scheduled:
            if now >= dueAt {
                entries[identifier] = Entry(dueAt: dueAt, state: .delivered)
                return false
            }
            return true
        }
    }

    mutating func markScheduled(identifier: String, dueAt: Date) {
        entries[identifier] = Entry(dueAt: dueAt, state: .scheduled)
    }

    mutating func markFailed(identifier: String, dueAt: Date, now: Date = Date()) {
        entries[identifier] = Entry(dueAt: dueAt, state: .failed, nextRetryAt: now.addingTimeInterval(60))
    }

    mutating func remove(identifier: String) {
        entries[identifier] = nil
    }

    mutating func keepOnly(_ identifiers: Set<String>) {
        entries = entries.filter { identifiers.contains($0.key) }
    }
}
