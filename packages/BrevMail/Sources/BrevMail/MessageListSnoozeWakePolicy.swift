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
    let header: MessageHeader?

    init(
        sourceMessageID: SourceMessageID,
        headerDate: Date,
        threadID: String?,
        header: MessageHeader? = nil
    ) {
        self.sourceMessageID = sourceMessageID
        self.headerDate = headerDate
        self.threadID = threadID
        self.header = header
    }
}

enum MessageListSnoozeWakePolicy {
    static func hasExpiredSourceOwnedSnooze(
        in snoozes: [LocalMessageSnooze],
        sourceID: MailSourceID,
        now: Date
    ) -> Bool {
        snoozes.contains { $0.messageID.sourceID == sourceID && $0.wakeAt <= now }
    }

    static func expiredInboxWakeCandidates(
        from candidates: [LocalMessageWorkflowCandidate],
        sourceID: MailSourceID,
        inboxFolderID: Folder.ID,
        loadedHeaders: [MessageHeader],
        snoozes: [LocalMessageSnooze],
        now: Date
    ) -> [MessageHeader] {
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: LocalMessageWorkflowState(snoozes: snoozes),
            now: now
        )
        let loadedIDs = Set(loadedHeaders.map(\.id))
        var seenIDs = Set<MessageHeader.ID>()

        return candidates.compactMap { candidate in
            let header = candidate.header
            guard candidate.sourceID == sourceID,
                  header.folderID == inboxFolderID,
                  !loadedIDs.contains(header.id),
                  seenIDs.insert(header.id).inserted,
                  let snooze = projection.snooze(
                      for: SourceMessageID(sourceID: sourceID, messageID: header.id),
                      header: header
                  ),
                  snooze.wakeAt <= now else {
                return nil
            }
            return header
        }
    }

    static func effectiveDateOverrides(
        for entries: [MessageListSnoozeWakeEntry],
        snoozes: [LocalMessageSnooze],
        now: Date,
        projection: LocalMessageWorkflowConversationProjection? = nil
    ) -> [SourceMessageID: Date] {
        let state = LocalMessageWorkflowState(snoozes: snoozes)
        let workflowProjection = projection ?? LocalMessageWorkflowConversationProjection(
            candidates: entries.compactMap { entry in
                entry.header.map { .init(sourceID: entry.sourceMessageID.sourceID, header: $0) }
            },
            state: state,
            now: now
        )
        var expiredWakeDates: [SourceMessageID: Date] = [:]
        for entry in entries {
            let snooze = entry.header.map { workflowProjection.snooze(for: entry.sourceMessageID, header: $0) }
                ?? workflowProjection.snooze(for: entry.sourceMessageID)
            guard let snooze, snooze.wakeAt <= now else { continue }
            expiredWakeDates[entry.sourceMessageID] = snooze.wakeAt
        }

        var effectiveDates: [SourceMessageID: Date] = [:]
        var latestLegacyDateByThread: [ThreadKey: Date] = [:]
        var legacyThreadWakeDates: [ThreadKey: Date] = [:]
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
                latestLegacyDateByThread[key] = max(latestLegacyDateByThread[key] ?? .distantPast, entry.headerDate)
                let snooze = entry.header.map { workflowProjection.snooze(for: entry.sourceMessageID, header: $0) }
                    ?? workflowProjection.snooze(for: entry.sourceMessageID)
                if let wakeAt = expiredWakeDates[entry.sourceMessageID],
                   snooze?.conversationMetadata == nil {
                    latestLegacyDateByThread[key] = max(latestLegacyDateByThread[key] ?? .distantPast, effectiveDate)
                    legacyThreadWakeDates[key] = max(legacyThreadWakeDates[key] ?? .distantPast, wakeAt)
                }
            }
        }

        var overrides: [SourceMessageID: Date] = [:]
        for entry in entries {
            let effectiveDate: Date
            if let threadID = entry.threadID {
                let key = ThreadKey(sourceID: entry.sourceMessageID.sourceID, threadID: threadID)
                let ownEffectiveDate = effectiveDates[entry.sourceMessageID] ?? entry.headerDate
                effectiveDate = legacyThreadWakeDates[key] == nil
                    ? ownEffectiveDate
                    : max(ownEffectiveDate, latestLegacyDateByThread[key] ?? entry.headerDate)
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
