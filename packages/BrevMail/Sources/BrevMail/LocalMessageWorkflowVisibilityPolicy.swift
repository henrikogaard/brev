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

enum LocalMessageWorkflowVisibilityMode: Sendable, Hashable {
    case active
    case snoozed
    case done
    case search
}

/// Changes only when a rolling-time predicate can change list membership.
/// Including this in presentation cache keys keeps time-dependent filtering
/// deterministic without invalidating every selection-only redraw.
struct MailboxListTemporalInvalidationKey: Equatable, Sendable {
    let expiredSnoozeCount: Int
    let lastWeekIncludedCount: Int

    static func headers(
        _ headers: [MessageHeader],
        filter: MailboxFilterQuery,
        workflowMode: LocalMessageWorkflowVisibilityMode,
        workflowState: LocalMessageWorkflowState,
        now: Date
    ) -> MailboxListTemporalInvalidationKey {
        make(
            dates: headers.lazy.map(\.date),
            filter: filter,
            workflowMode: workflowMode,
            workflowState: workflowState,
            now: now
        )
    }

    static func items(
        _ items: [UnifiedInboxItem],
        filter: MailboxFilterQuery,
        workflowMode: LocalMessageWorkflowVisibilityMode,
        workflowState: LocalMessageWorkflowState,
        now: Date
    ) -> MailboxListTemporalInvalidationKey {
        make(
            dates: items.lazy.map(\.header.date),
            filter: filter,
            workflowMode: workflowMode,
            workflowState: workflowState,
            now: now
        )
    }

    private static func make<Dates: Sequence>(
        dates: Dates,
        filter: MailboxFilterQuery,
        workflowMode: LocalMessageWorkflowVisibilityMode,
        workflowState: LocalMessageWorkflowState,
        now: Date
    ) -> MailboxListTemporalInvalidationKey where Dates.Element == Date {
        let expiredSnoozeCount = switch workflowMode {
        case .active, .snoozed:
            workflowState.snoozes.lazy.filter { $0.wakeAt <= now }.count
        case .done, .search:
            0
        }
        let lastWeekIncludedCount = filter.activeFilters.contains(.lastWeek)
            ? dates.lazy.filter { $0 > now.addingTimeInterval(-604_800) }.count
            : 0
        return MailboxListTemporalInvalidationKey(
            expiredSnoozeCount: expiredSnoozeCount,
            lastWeekIncludedCount: lastWeekIncludedCount
        )
    }
}

enum LocalMessageWorkflowVisibilityPolicy {
    static func headers(
        _ headers: [MessageHeader],
        sourceID: MailSourceID,
        mode: LocalMessageWorkflowVisibilityMode,
        state: LocalMessageWorkflowState,
        now: Date = Date()
    ) -> [MessageHeader] {
        headers.filter { header in
            matches(
                SourceMessageID(sourceID: sourceID, messageID: header.id),
                mode: mode,
                state: state,
                now: now
            )
        }
    }

    static func items(
        _ items: [UnifiedInboxItem],
        mode: LocalMessageWorkflowVisibilityMode,
        state: LocalMessageWorkflowState,
        now: Date = Date()
    ) -> [UnifiedInboxItem] {
        items.filter { item in
            matches(
                SourceMessageID(sourceID: item.sourceID, messageID: item.header.id),
                mode: mode,
                state: state,
                now: now
            )
        }
    }

    private static func matches(
        _ messageID: SourceMessageID,
        mode: LocalMessageWorkflowVisibilityMode,
        state: LocalMessageWorkflowState,
        now: Date
    ) -> Bool {
        switch mode {
        case .active:
            return !state.isDone(messageID)
                && !state.isSnoozed(messageID, at: now)
        case .snoozed:
            return state.isSnoozed(messageID, at: now)
        case .done:
            return state.isDone(messageID)
        case .search:
            return true
        }
    }
}
