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
import Observation

/// One conversation queued for sequential triage (#293).
struct TriageItem: Identifiable, Equatable, Sendable {
    let sourceID: MailSourceID
    /// The representative newest message header for this conversation.
    let header: MessageHeader
    /// All messages in the conversation, ordered oldest to newest.
    let threadHeaders: [MessageHeader]

    var id: SourceMessageID {
        SourceMessageID(sourceID: sourceID, messageID: header.id)
    }
}

/// Captures where the user was in the mailbox before entering Triage so
/// pressing Escape or Done returns to the exact same position (#293).
struct TriageReturnPosition: Equatable, Sendable {
    let selectedSourceID: MailSourceID?
    let selectedFolderID: Folder.ID?
    let selectedMessageID: MessageHeader.ID?
    let isUnifiedInboxSelected: Bool
    let isSmartViewSelected: Bool
}

/// Single-key decisions supported inside Triage mode (#293).
enum TriageKeyAction: Equatable, Sendable {
    case archive
    case snooze
    case reply
    case skip
    case done
}

/// Pure key-binding policy for Triage mode, kept isolated so tests can verify
/// typing safety and capability gating without AppKit events.
enum TriageKeyboardPolicy {
    /// Resolves a key press into a triage action, returning nil when typing in
    /// a text field, when command/control/option modifiers are held, or when
    /// snooze is unavailable.
    static func action(
        for characters: String,
        hasModifier: Bool,
        isEditingText: Bool,
        canSnooze: Bool
    ) -> TriageKeyAction? {
        guard !isEditingText else { return nil }
        if characters == "\u{1B}" {
            return hasModifier ? nil : .done
        }
        guard !hasModifier else { return nil }
        switch characters.lowercased() {
        case "e":
            return .archive
        case "h":
            return canSnooze ? .snooze : nil
        case "r":
            return .reply
        case "j":
            return .skip
        default:
            return nil
        }
    }
}

/// Builds an ordered, conversation-deduplicated triage queue from the active
/// mailbox headers while skipping already snoozed or done items.
enum TriageQueueBuilder {
    static func build(
        entries: [(MailSourceID, MessageHeader)],
        workflowState: LocalMessageWorkflowState,
        now: Date = Date()
    ) -> [TriageItem] {
        let lookup = LocalMessageWorkflowLookup(state: workflowState)
        struct ConversationKey: Hashable {
            let sourceID: MailSourceID
            let threadID: String
        }

        var orderedKeys: [ConversationKey] = []
        var grouped: [ConversationKey: [MessageHeader]] = [:]

        for (sourceID, header) in entries {
            let messageID = SourceMessageID(sourceID: sourceID, messageID: header.id)
            if lookup.activeSnooze(for: messageID, at: now) != nil || lookup.isDone(messageID) {
                continue
            }
            let threadKey = header.threadID.isEmpty ? header.id : header.threadID
            let key = ConversationKey(sourceID: sourceID, threadID: threadKey)
            if grouped[key] == nil {
                orderedKeys.append(key)
                grouped[key] = [header]
            } else {
                grouped[key, default: []].append(header)
            }
        }

        return orderedKeys.compactMap { key in
            guard let members = grouped[key], !members.isEmpty else { return nil }
            let chronological = members.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
            guard let representative = chronological.last else { return nil }
            return TriageItem(
                sourceID: key.sourceID,
                header: representative,
                threadHeaders: chronological
            )
        }
    }
}

/// Localized copy helpers for Triage mode (#293).
enum TriagePresentation {
    /// Window/bar title such as "Triage, 184 left" or "Triage" when complete.
    static func title(remainingCount: Int, locale: Locale = .current) -> String {
        guard remainingCount > 0 else {
            return String(localized: "Triage", bundle: .module, locale: locale)
        }
        return String(
            format: String(localized: "Triage, %lld left", bundle: .module, locale: locale),
            locale: locale,
            Int64(remainingCount)
        )
    }
}

/// Holds the active sequential triage queue, preloaded next bodies, and
/// undo-aware decision transitions (#293).
@Observable
@MainActor
final class TriageSession {
    /// Remaining and skipped conversations in this session.
    private(set) var items: [TriageItem]
    /// Zero-based position in `items`; equals `items.count` when caught up.
    private(set) var currentIndex = 0
    /// Total conversations queued when the session started.
    let totalInitialCount: Int
    /// Saved mailbox selection to restore when exiting Triage.
    let returnPosition: TriageReturnPosition
    /// Whether an async backend mutation (archive) is currently running.
    private(set) var isPerformingAction = false
    /// Non-fatal error surfaced inline if an archive fails.
    private(set) var errorMessage: String?

    private var preloadedBodies: [SourceMessageID: MessageBody] = [:]
    private var preloadTask: Task<Void, Never>?

    /// Creates a triage session for the given ordered conversations.
    init(items: [TriageItem], returnPosition: TriageReturnPosition) {
        self.items = items
        totalInitialCount = items.count
        self.returnPosition = returnPosition
    }

    /// Number of conversations left from the current position through the end.
    var remainingCount: Int {
        max(0, items.count - currentIndex)
    }

    /// Fraction of the initial queue already handled (0.0...1.0).
    var progress: Double {
        guard totalInitialCount > 0 else { return 1 }
        let handled = max(0, totalInitialCount - remainingCount)
        return min(1, Double(handled) / Double(totalInitialCount))
    }

    /// The conversation currently presented in the reader, or nil when done.
    var currentItem: TriageItem? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    /// The conversation immediately after the current one, used for body preloading.
    var nextItem: TriageItem? {
        let nextIndex = currentIndex + 1
        guard nextIndex >= 0, nextIndex < items.count else { return nil }
        return items[nextIndex]
    }

    /// Returns a preloaded body for `id` when already warmed in memory.
    func preloadedBody(for id: SourceMessageID) -> MessageBody? {
        preloadedBodies[id]
    }

    /// Cancels any in-flight body preload (for example when exiting Triage).
    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
    }

    /// Starts preloading the next conversation's body in the background so
    /// advancing does not flash a loading skeleton.
    func schedulePreloadNext(using loader: @escaping @Sendable (TriageItem) async -> MessageBody?) {
        preloadTask?.cancel()
        preloadTask = nil
        guard let next = nextItem, preloadedBodies[next.id] == nil else { return }
        preloadTask = Task { [weak self] in
            let body = await loader(next)
            guard !Task.isCancelled, let body, let self else { return }
            preloadedBodies[next.id] = body
        }
    }

    /// Synchronously awaits preloading the next item (used in deterministic tests).
    func preloadNextNow(using loader: @escaping @Sendable (TriageItem) async -> MessageBody?) async {
        guard let next = nextItem, preloadedBodies[next.id] == nil else { return }
        if let body = await loader(next) {
            preloadedBodies[next.id] = body
        }
    }

    /// Skips the current conversation, advancing to the next and registering an
    /// undo step on the shared `UndoQueue` so ⌘Z steps back to it.
    func skipCurrent(registeringUndoIn undoQueue: UndoQueue) {
        guard currentIndex < items.count else { return }
        errorMessage = nil
        let previousIndex = currentIndex
        currentIndex += 1
        let restoreSkip: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            currentIndex = min(previousIndex, max(0, items.count - 1))
            errorMessage = nil
        }
        undoQueue.push(UndoableMutation(description: String(localized: "Skipped", bundle: .module)) {
            await restoreSkip()
        })
    }

    /// Archives the current conversation through the caller's backend mutation,
    /// removing it from the triage queue and registering a reversible undo action.
    @discardableResult
    func archiveCurrent(
        undoQueue: UndoQueue,
        performArchive: @MainActor (TriageItem) async throws -> (@Sendable () async throws -> Void)
    ) async -> Bool {
        guard !isPerformingAction, let item = currentItem else { return false }
        let removedIndex = currentIndex
        isPerformingAction = true
        errorMessage = nil
        let lease = undoQueue.beginMutation()
        defer {
            isPerformingAction = false
            undoQueue.endMutation(lease)
        }

        items.remove(at: removedIndex)
        do {
            let undoBackend = try await performArchive(item)
            let restoreItem: @MainActor @Sendable () -> Void = { [weak self] in
                self?.restore(item, at: removedIndex)
            }
            undoQueue.push(
                UndoableMutation(description: String(localized: "Archived", bundle: .module)) {
                    try await undoBackend()
                    await restoreItem()
                },
                lease: lease
            )
            return true
        } catch {
            restore(item, at: removedIndex)
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Snoozes the current conversation until tomorrow morning (09:00) using
    /// `SnoozeQuickOption.tomorrowMorning` and registers a reversible undo action.
    @discardableResult
    func snoozeCurrentUntilTomorrow(
        now: Date = Date(),
        calendar: Calendar = .current,
        undoQueue: UndoQueue,
        applySnooze: @MainActor (TriageItem, Date) -> (@MainActor @Sendable () -> Void)
    ) -> Bool {
        guard !isPerformingAction,
              let item = currentItem,
              let wakeDate = SnoozeQuickOption.tomorrowMorning.wakeDate(now: now, calendar: calendar)
        else { return false }
        let removedIndex = currentIndex
        errorMessage = nil
        items.remove(at: removedIndex)
        let undoWorkflow = applySnooze(item, wakeDate)
        let restoreSnooze: @MainActor @Sendable () -> Void = { [weak self] in
            undoWorkflow()
            self?.restore(item, at: removedIndex)
        }
        undoQueue.push(UndoableMutation(description: String(localized: "Snoozed until tomorrow", bundle: .module)) {
            await restoreSnooze()
        })
        return true
    }

    /// Reinserts a previously removed conversation at its original index and
    /// focuses it again after Undo or a failed mutation.
    func restore(_ item: TriageItem, at index: Int) {
        let clamped = max(0, min(index, items.count))
        if !items.contains(where: { $0.id == item.id }) {
            items.insert(item, at: clamped)
        }
        currentIndex = clamped
        errorMessage = nil
    }
}
