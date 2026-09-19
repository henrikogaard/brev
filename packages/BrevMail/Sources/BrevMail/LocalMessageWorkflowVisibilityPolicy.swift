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
        MailboxListTemporalInvalidationKey(
            expiredSnoozeCount: expiredSnoozeCount(
                workflowMode: workflowMode,
                workflowState: workflowState,
                now: now
            ),
            lastWeekIncludedCount: filter.activeFilters.contains(.lastWeek)
                ? dates.lazy.filter { $0 > lastWeekCutoff(now) }.count
                : 0
        )
    }

    static func expiredSnoozeCount(
        workflowMode: LocalMessageWorkflowVisibilityMode,
        workflowState: LocalMessageWorkflowState,
        now: Date
    ) -> Int {
        switch workflowMode {
        case .active, .snoozed:
            workflowState.snoozes.lazy.filter { $0.wakeAt <= now }.count
        case .done, .search:
            0
        }
    }

    static func lastWeekCutoff(_ now: Date) -> Date {
        now.addingTimeInterval(-604_800)
    }
}

/// Memoizes the last-week membership scan inside
/// `MailboxListTemporalInvalidationKey` so building the presentation-cache
/// key no longer walks every header date on each body evaluation.
///
/// The window cutoff only moves forward, and membership can only shrink once
/// it reaches the oldest date still inside the window — so a previous scan
/// stays valid until `now` crosses that date or the source buffer changes.
/// Results therefore match the direct scan exactly.
final class MailboxListTemporalInvalidationTracker {
    private struct LastWeekWindow {
        var cutoff = Date.distantPast
        var includedCount = 0
        var oldestIncludedDate: Date?
    }

    private var headersWindow = LastWeekWindow()
    private var itemsWindow = LastWeekWindow()
    /// Retained so the buffer-identity check stays sound — a stored array's
    /// backing storage cannot be freed and reallocated while we hold it.
    private var retainedHeaders: [MessageHeader]?
    private var retainedItems: [UnifiedInboxItem]?

    func key(
        headers: [MessageHeader],
        filter: MailboxFilterQuery,
        workflowMode: LocalMessageWorkflowVisibilityMode,
        workflowState: LocalMessageWorkflowState,
        now: Date
    ) -> MailboxListTemporalInvalidationKey {
        let key = MailboxListTemporalInvalidationKey(
            expiredSnoozeCount: MailboxListTemporalInvalidationKey.expiredSnoozeCount(
                workflowMode: workflowMode,
                workflowState: workflowState,
                now: now
            ),
            lastWeekIncludedCount: lastWeekIncludedCount(
                dates: headers.lazy.map(\.date),
                filter: filter,
                now: now,
                sourceUnchanged: retainedHeaders.map {
                    headers.sharesRetainedBuffer(with: $0)
                } ?? false,
                window: &headersWindow
            )
        )
        if filter.activeFilters.contains(.lastWeek) {
            retainedHeaders = headers
        }
        return key
    }

    func key(
        items: [UnifiedInboxItem],
        filter: MailboxFilterQuery,
        workflowMode: LocalMessageWorkflowVisibilityMode,
        workflowState: LocalMessageWorkflowState,
        now: Date
    ) -> MailboxListTemporalInvalidationKey {
        let key = MailboxListTemporalInvalidationKey(
            expiredSnoozeCount: MailboxListTemporalInvalidationKey.expiredSnoozeCount(
                workflowMode: workflowMode,
                workflowState: workflowState,
                now: now
            ),
            lastWeekIncludedCount: lastWeekIncludedCount(
                dates: items.lazy.map(\.header.date),
                filter: filter,
                now: now,
                sourceUnchanged: retainedItems.map {
                    items.sharesRetainedBuffer(with: $0)
                } ?? false,
                window: &itemsWindow
            )
        )
        if filter.activeFilters.contains(.lastWeek) {
            retainedItems = items
        }
        return key
    }

    private func lastWeekIncludedCount<Dates: Sequence>(
        dates: Dates,
        filter: MailboxFilterQuery,
        now: Date,
        sourceUnchanged: Bool,
        window: inout LastWeekWindow
    ) -> Int where Dates.Element == Date {
        guard filter.activeFilters.contains(.lastWeek) else { return 0 }
        let cutoff = MailboxListTemporalInvalidationKey.lastWeekCutoff(now)
        if sourceUnchanged,
           cutoff >= window.cutoff,
           window.oldestIncludedDate.map({ cutoff < $0 }) ?? true {
            return window.includedCount
        }
        var count = 0
        var oldest: Date?
        for date in dates where date > cutoff {
            count += 1
            if oldest.map({ date < $0 }) ?? true {
                oldest = date
            }
        }
        window = LastWeekWindow(
            cutoff: cutoff,
            includedCount: count,
            oldestIncludedDate: oldest
        )
        return count
    }
}

/// Pre-materialized membership view of `LocalMessageWorkflowState`. Built
/// once per list rebuild (or shared across a body evaluation) so per-message
/// checks are O(1) lookups instead of linear scans of `snoozes`,
/// `doneMessages`, and `notes` for every row.
struct LocalMessageWorkflowLookup: Sendable {
    private let snoozesByMessageID: [SourceMessageID: LocalMessageSnooze]
    private let doneMessageIDs: Set<SourceMessageID>
    private let notesByMessageID: [SourceMessageID: LocalMessageNote]

    init(state: LocalMessageWorkflowState) {
        snoozesByMessageID = Dictionary(
            state.snoozes.map { ($0.messageID, $0) },
            uniquingKeysWith: { _, last in last }
        )
        doneMessageIDs = Set(state.doneMessages.map(\.messageID))
        notesByMessageID = Dictionary(
            state.notes.map { ($0.messageID, $0) },
            uniquingKeysWith: { _, last in last }
        )
    }

    func activeSnooze(
        for messageID: SourceMessageID,
        at now: Date = Date()
    ) -> LocalMessageSnooze? {
        guard let snooze = snoozesByMessageID[messageID], snooze.isActive(at: now) else {
            return nil
        }
        return snooze
    }

    func isSnoozed(_ messageID: SourceMessageID, at now: Date = Date()) -> Bool {
        activeSnooze(for: messageID, at: now) != nil
    }

    func isDone(_ messageID: SourceMessageID) -> Bool {
        doneMessageIDs.contains(messageID)
    }

    func note(for messageID: SourceMessageID) -> LocalMessageNote? {
        notesByMessageID[messageID]
    }
}

/// Memoizes `LocalMessageWorkflowLookup` across body evaluations: the
/// materialization is a pure function of the workflow state, which is
/// `Equatable`, so it only needs rebuilding when the state value changes.
final class LocalMessageWorkflowLookupCache {
    private var state: LocalMessageWorkflowState?
    private var lookup = LocalMessageWorkflowLookup(state: .defaults)

    func lookup(for state: LocalMessageWorkflowState) -> LocalMessageWorkflowLookup {
        if self.state != state {
            self.state = state
            lookup = LocalMessageWorkflowLookup(state: state)
        }
        return lookup
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
        let lookup = LocalMessageWorkflowLookup(state: state)
        return headers.filter { header in
            matches(
                SourceMessageID(sourceID: sourceID, messageID: header.id),
                mode: mode,
                lookup: lookup,
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
        let lookup = LocalMessageWorkflowLookup(state: state)
        return items.filter { item in
            matches(
                SourceMessageID(sourceID: item.sourceID, messageID: item.header.id),
                mode: mode,
                lookup: lookup,
                now: now
            )
        }
    }

    private static func matches(
        _ messageID: SourceMessageID,
        mode: LocalMessageWorkflowVisibilityMode,
        lookup: LocalMessageWorkflowLookup,
        now: Date
    ) -> Bool {
        switch mode {
        case .active:
            return !lookup.isDone(messageID)
                && !lookup.isSnoozed(messageID, at: now)
        case .snoozed:
            return lookup.isSnoozed(messageID, at: now)
        case .done:
            return lookup.isDone(messageID)
        case .search:
            return true
        }
    }
}
