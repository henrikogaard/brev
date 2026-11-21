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

struct MessageListSnoozeWakeEntry: Sendable {
    let sourceMessageID: SourceMessageID
    let headerDate: Date
    let threadID: String?
}

enum MessageListSnoozeWakePolicy {
    static func effectiveDateOverrides(
        for entries: [MessageListSnoozeWakeEntry],
        snoozes: [LocalMessageSnooze],
        now: Date
    ) -> [SourceMessageID: Date] {
        var expiredWakeDates: [SourceMessageID: Date] = [:]
        for snooze in snoozes where snooze.wakeAt <= now {
            expiredWakeDates[snooze.messageID] = max(
                expiredWakeDates[snooze.messageID] ?? .distantPast,
                snooze.wakeAt
            )
        }

        var effectiveDates: [SourceMessageID: Date] = [:]
        var latestDateByThread: [ThreadKey: Date] = [:]
        var latestWakeDateByThread: [ThreadKey: Date] = [:]
        for entry in entries {
            let effectiveDate = max(
                entry.headerDate,
                expiredWakeDates[entry.sourceMessageID] ?? .distantPast
            )
            effectiveDates[entry.sourceMessageID] = max(
                effectiveDates[entry.sourceMessageID] ?? .distantPast,
                effectiveDate
            )
            if let threadID = entry.threadID {
                let key = ThreadKey(sourceID: entry.sourceMessageID.sourceID, threadID: threadID)
                latestDateByThread[key] = max(latestDateByThread[key] ?? .distantPast, effectiveDate)
                if let wakeAt = expiredWakeDates[entry.sourceMessageID] {
                    latestWakeDateByThread[key] = max(latestWakeDateByThread[key] ?? .distantPast, wakeAt)
                }
            }
        }

        var overrides: [SourceMessageID: Date] = [:]
        for entry in entries {
            let effectiveDate: Date
            if let threadID = entry.threadID {
                let key = ThreadKey(sourceID: entry.sourceMessageID.sourceID, threadID: threadID)
                effectiveDate = latestWakeDateByThread[key] == nil
                    ? effectiveDates[entry.sourceMessageID] ?? entry.headerDate
                    : latestDateByThread[key] ?? entry.headerDate
            } else {
                effectiveDate = effectiveDates[entry.sourceMessageID] ?? entry.headerDate
            }
            if effectiveDate > entry.headerDate {
                overrides[entry.sourceMessageID] = effectiveDate
            }
        }
        return overrides
    }

    static func nearestWakeDate(
        in snoozes: [LocalMessageSnooze],
        sourceIDs: Set<MailSourceID>,
        after now: Date
    ) -> Date? {
        snoozes.lazy
            .filter { sourceIDs.contains($0.messageID.sourceID) && $0.wakeAt > now }
            .map(\.wakeAt)
            .min()
    }

    static func sleepNanoseconds(until wakeAt: Date, now: Date) -> UInt64 {
        let interval = max(0, wakeAt.timeIntervalSince(now))
        let boundedNanoseconds = min(interval * 1_000_000_000, Double(Int64.max))
        return UInt64(boundedNanoseconds)
    }

    static func shouldPromoteInboxWake(
        isInbox: Bool,
        isNewestFirst: Bool,
        hasActiveSearch: Bool,
        isSmartView: Bool,
        isSavedSearch: Bool
    ) -> Bool {
        isInbox && isNewestFirst && !hasActiveSearch && !isSmartView && !isSavedSearch
    }

    private struct ThreadKey: Hashable {
        let sourceID: MailSourceID
        let threadID: String
    }
}
