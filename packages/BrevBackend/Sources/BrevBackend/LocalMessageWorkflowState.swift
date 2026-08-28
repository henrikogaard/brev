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

/// Local, provider-neutral snooze state for one message.
///
/// Snoozes are keyed by `SourceMessageID` so identical provider message
/// identifiers in separate mailboxes do not collide.
public struct LocalMessageSnooze: Codable, Equatable, Identifiable, Sendable {
    public let messageID: SourceMessageID
    public var wakeAt: Date
    public let createdAt: Date

    public init(
        messageID: SourceMessageID,
        wakeAt: Date,
        createdAt: Date = Date()
    ) {
        self.messageID = messageID
        self.wakeAt = wakeAt
        self.createdAt = createdAt
    }

    public var id: SourceMessageID { messageID }

    public func isActive(at now: Date = Date()) -> Bool {
        wakeAt > now
    }
}

/// Local, provider-neutral Inbox Zero state for one message.
public struct LocalMessageDone: Codable, Equatable, Identifiable, Sendable {
    public let messageID: SourceMessageID
    public let completedAt: Date

    public init(messageID: SourceMessageID, completedAt: Date = Date()) {
        self.messageID = messageID
        self.completedAt = completedAt
    }

    public var id: SourceMessageID { messageID }
}

/// Local, provider-neutral note for one message.
public struct LocalMessageNote: Codable, Equatable, Identifiable, Sendable {
    public let messageID: SourceMessageID
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        messageID: SourceMessageID,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.messageID = messageID
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var id: SourceMessageID { messageID }
}

/// Persisted local message workflow state.
///
/// This state is Brev-local presentation/workflow state. It never mutates
/// provider folders or message flags.
public struct LocalMessageWorkflowState: Codable, Equatable, Sendable {
    public var snoozes: [LocalMessageSnooze]
    public var doneMessages: [LocalMessageDone]
    public var notes: [LocalMessageNote]

    public init(
        snoozes: [LocalMessageSnooze] = [],
        doneMessages: [LocalMessageDone] = [],
        notes: [LocalMessageNote] = []
    ) {
        self.snoozes = Self.normalizedSnoozes(snoozes)
        self.doneMessages = Self.normalizedDone(doneMessages)
        self.notes = Self.normalizedNotes(notes)
    }

    public static let defaults = LocalMessageWorkflowState()

    public func activeSnooze(
        for messageID: SourceMessageID,
        at now: Date = Date()
    ) -> LocalMessageSnooze? {
        snoozes.first { $0.messageID == messageID && $0.isActive(at: now) }
    }

    public func isSnoozed(
        _ messageID: SourceMessageID,
        at now: Date = Date()
    ) -> Bool {
        activeSnooze(for: messageID, at: now) != nil
    }

    public func isDone(_ messageID: SourceMessageID) -> Bool {
        doneMessages.contains { $0.messageID == messageID }
    }

    public func note(for messageID: SourceMessageID) -> LocalMessageNote? {
        notes.first { $0.messageID == messageID }
    }

    enum CodingKeys: String, CodingKey {
        case snoozes
        case doneMessages
        case notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            snoozes: container.decodeIfPresent([LocalMessageSnooze].self, forKey: .snoozes) ?? [],
            doneMessages: container.decodeIfPresent([LocalMessageDone].self, forKey: .doneMessages) ?? [],
            notes: container.decodeIfPresent([LocalMessageNote].self, forKey: .notes) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(snoozes, forKey: .snoozes)
        try container.encode(doneMessages, forKey: .doneMessages)
        try container.encode(notes, forKey: .notes)
    }

    private static func normalizedSnoozes(
        _ snoozes: [LocalMessageSnooze]
    ) -> [LocalMessageSnooze] {
        var indexesByMessageID: [SourceMessageID: Int] = [:]
        var result: [LocalMessageSnooze] = []
        for snooze in snoozes {
            if let index = indexesByMessageID[snooze.messageID] {
                result[index] = snooze
            } else {
                indexesByMessageID[snooze.messageID] = result.count
                result.append(snooze)
            }
        }
        return result
    }

    private static func normalizedDone(
        _ doneMessages: [LocalMessageDone]
    ) -> [LocalMessageDone] {
        var indexesByMessageID: [SourceMessageID: Int] = [:]
        var result: [LocalMessageDone] = []
        for done in doneMessages {
            if let index = indexesByMessageID[done.messageID] {
                result[index] = done
            } else {
                indexesByMessageID[done.messageID] = result.count
                result.append(done)
            }
        }
        return result
    }

    private static func normalizedNotes(
        _ notes: [LocalMessageNote]
    ) -> [LocalMessageNote] {
        var indexesByMessageID: [SourceMessageID: Int] = [:]
        var result: [LocalMessageNote] = []
        for note in notes {
            if let index = indexesByMessageID[note.messageID] {
                result[index] = note
            } else {
                indexesByMessageID[note.messageID] = result.count
                result.append(note)
            }
        }
        return result
    }
}

public enum LocalMessageWorkflowStatePolicy {
    public static func snoozing(
        _ messageID: SourceMessageID,
        until wakeAt: Date,
        now: Date = Date(),
        in state: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowState {
        var snoozes = state.snoozes.filter { $0.messageID != messageID }
        snoozes.append(LocalMessageSnooze(
            messageID: messageID,
            wakeAt: wakeAt,
            createdAt: now
        ))
        return LocalMessageWorkflowState(
            snoozes: snoozes,
            doneMessages: state.doneMessages,
            notes: state.notes
        )
    }

    public static func clearingSnooze(
        _ messageIDs: [SourceMessageID],
        in state: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowState {
        let ids = Set(messageIDs)
        return LocalMessageWorkflowState(
            snoozes: state.snoozes.filter { !ids.contains($0.messageID) },
            doneMessages: state.doneMessages,
            notes: state.notes
        )
    }

    public static func markingDone(
        _ messageIDs: [SourceMessageID],
        now: Date = Date(),
        in state: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowState {
        let ids = Set(messageIDs)
        let retained = state.doneMessages.filter { !ids.contains($0.messageID) }
        let added = messageIDs.map {
            LocalMessageDone(messageID: $0, completedAt: now)
        }
        return LocalMessageWorkflowState(
            snoozes: state.snoozes,
            doneMessages: retained + added,
            notes: state.notes
        )
    }

    public static func clearingDone(
        _ messageIDs: [SourceMessageID],
        in state: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowState {
        let ids = Set(messageIDs)
        return LocalMessageWorkflowState(
            snoozes: state.snoozes,
            doneMessages: state.doneMessages.filter { !ids.contains($0.messageID) },
            notes: state.notes
        )
    }

    public static func savingNote(
        for messageID: SourceMessageID,
        body: String,
        now: Date = Date(),
        in state: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowState {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = state.notes.filter { $0.messageID != messageID }
        if !trimmed.isEmpty {
            let createdAt = state.note(for: messageID)?.createdAt ?? now
            notes.append(LocalMessageNote(
                messageID: messageID,
                body: trimmed,
                createdAt: createdAt,
                updatedAt: now
            ))
        }
        return LocalMessageWorkflowState(
            snoozes: state.snoozes,
            doneMessages: state.doneMessages,
            notes: notes
        )
    }

    public static func removingAccount(
        _ accountID: BrevAccount.ID,
        from state: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowState {
        LocalMessageWorkflowState(
            snoozes: state.snoozes.filter {
                $0.messageID.sourceID.accountID != accountID
            },
            doneMessages: state.doneMessages.filter {
                $0.messageID.sourceID.accountID != accountID
            },
            notes: state.notes.filter {
                $0.messageID.sourceID.accountID != accountID
            }
        )
    }
}

public enum LocalMessageWorkflowStateStorage {
    public static let storageKey = "message.workflowState.v1"

    public static func load(
        from defaults: UserDefaults = .standard
    ) -> LocalMessageWorkflowState {
        guard let data = defaults.data(forKey: storageKey) else {
            return .defaults
        }
        return decode(data) ?? .defaults
    }

    public static func save(
        _ state: LocalMessageWorkflowState,
        to defaults: UserDefaults = .standard
    ) {
        guard let data = encode(state) else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    public static func removeAccount(
        _ accountID: BrevAccount.ID,
        from defaults: UserDefaults = .standard
    ) {
        save(
            LocalMessageWorkflowStatePolicy.removingAccount(
                accountID,
                from: load(from: defaults)
            ),
            to: defaults
        )
    }

    public static func decode(_ data: Data) -> LocalMessageWorkflowState? {
        try? JSONDecoder().decode(LocalMessageWorkflowState.self, from: data)
    }

    public static func encode(_ state: LocalMessageWorkflowState) -> Data? {
        try? JSONEncoder().encode(state)
    }
}
