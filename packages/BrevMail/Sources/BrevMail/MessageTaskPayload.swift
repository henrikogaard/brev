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
import BrevCalendar
import Foundation
#if canImport(EventKit)
@preconcurrency import EventKit
#endif

/// Where a Create Task draft lands (#12): Apple Reminders, the system
/// share sheet, or a writable PIM task list (Google Tasks or a
/// CalDAV VTODO collection).
struct MessageTaskTarget: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case appleReminders
        case systemShare
        /// The target task list's collection ID on a PIM tasks source.
        case providerTaskList(PIMCollection.ID)
    }

    let kind: Kind
    /// Display name for the picker row.
    let title: String

    var id: String {
        switch kind {
        case .appleReminders: "appleReminders"
        case .systemShare: "systemShare"
        case .providerTaskList(let id): "pim:\(id)"
        }
    }

    static let appleReminders = MessageTaskTarget(
        kind: .appleReminders,
        title: String(localized: "Reminders", bundle: .module)
    )
    static let systemShare = MessageTaskTarget(
        kind: .systemShare,
        title: String(localized: "Share", bundle: .module)
    )

    /// The built-in targets plus one entry per writable task list the
    /// editing model resolved — the sheet's picker options.
    static func all(
        providerTargets: [TaskWriteTarget]
    ) -> [MessageTaskTarget] {
        [appleReminders, systemShare]
            + providerTargets.map {
                MessageTaskTarget(
                    kind: .providerTaskList($0.collection.id),
                    title: $0.title
                )
            }
    }
}

struct MessageTaskDraft: Equatable, Sendable {
    var title: String
    var notes: String
    var dueDate: Date?
    var deepLink: URL
    var target: MessageTaskTarget

    var isCreateEnabled: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MessageTaskCreationResult: Equatable, Sendable {
    let message: String
}

protocol MessageTaskCreating {
    func createTask(from draft: MessageTaskDraft) async throws -> MessageTaskCreationResult
}

enum MessageTaskCreationError: LocalizedError, Equatable {
    case remindersUnavailable
    case remindersAccessDenied
    case unsupportedTarget
    case providerWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .remindersUnavailable:
            String(localized: "Apple Reminders is unavailable.", bundle: .module)
        case .remindersAccessDenied:
            String(localized: "Brev does not have permission to create reminders.", bundle: .module)
        case .unsupportedTarget:
            String(localized: "This task handoff target is unavailable.", bundle: .module)
        case .providerWriteFailed(let message):
            message
        }
    }
}

enum MessageTaskDeepLinkBuilder {
    static func url(
        for header: MessageHeader,
        accountID: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "brev"
        components.host = "message"
        components.queryItems = [
            URLQueryItem(name: "accountID", value: accountID),
            URLQueryItem(name: "folderID", value: header.folderID),
            URLQueryItem(name: "messageID", value: header.id)
        ]
        return components.url
    }
}

enum MessageTaskDraftBuilder {
    static func draft(
        for header: MessageHeader,
        accountID: String,
        dueDate: Date? = nil,
        target: MessageTaskTarget = .appleReminders
    ) -> MessageTaskDraft? {
        guard let deepLink = MessageTaskDeepLinkBuilder.url(
            for: header,
            accountID: accountID
        ) else {
            return nil
        }
        return MessageTaskDraft(
            title: title(for: header),
            notes: notes(for: header, deepLink: deepLink),
            dueDate: dueDate,
            deepLink: deepLink,
            target: target
        )
    }

    private static func title(for header: MessageHeader) -> String {
        let subject = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty {
            return subject
        }
        return "Email from \(header.from.displayName)"
    }

    private static func notes(for header: MessageHeader, deepLink: URL) -> String {
        [
            "From: \(displayString(header.from))",
            "Subject: \(title(for: header))",
            "Date: \(ISO8601DateFormatter().string(from: header.date))",
            previewLine(for: header),
            "Brev link: \(deepLink.absoluteString)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static func previewLine(for header: MessageHeader) -> String? {
        let snippet = header.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return nil }
        return "Preview: \(snippet)"
    }

    private static func displayString(_ correspondent: Correspondent) -> String {
        let name = correspondent.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            return correspondent.email
        }
        return "\(name) <\(correspondent.email)>"
    }
}

enum MessageTaskSharePayload {
    static func text(for draft: MessageTaskDraft) -> String {
        var parts = [draft.title]
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            parts.append(notes)
        }
        if let dueDate = draft.dueDate {
            parts.append("Due: \(dueDate.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: "\n\n")
    }
}

#if canImport(EventKit)
final class AppleReminderTaskCreator: MessageTaskCreating {
    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(
        eventStore: EKEventStore = EKEventStore(),
        calendar: Calendar = .current
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func createTask(from draft: MessageTaskDraft) async throws -> MessageTaskCreationResult {
        guard draft.target.kind == .appleReminders else {
            throw MessageTaskCreationError.unsupportedTarget
        }
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else {
            throw MessageTaskCreationError.remindersAccessDenied
        }
        guard let defaultCalendar = eventStore.defaultCalendarForNewReminders() else {
            throw MessageTaskCreationError.remindersUnavailable
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = defaultCalendar
        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = draft.notes
        if let dueDate = draft.dueDate {
            reminder.dueDateComponents = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }
        try eventStore.save(reminder, commit: true)
        return MessageTaskCreationResult(message: String(localized: "Task created in Reminders.", bundle: .module))
    }
}
#else
struct AppleReminderTaskCreator: MessageTaskCreating {
    func createTask(from draft: MessageTaskDraft) async throws -> MessageTaskCreationResult {
        throw MessageTaskCreationError.remindersUnavailable
    }
}
#endif

/// Creates a task in a writable PIM task list (Google Tasks or a
/// CalDAV VTODO collection) from a Create Task draft (#12).
///
/// Resolves the draft's target list through the editing model at call
/// time so a stale or freshly-enabled list never writes to the wrong
/// place. The message's brev:// deep link rides in the task's links so
/// the provider record keeps a path back to the mail.
struct PIMTaskMessageCreator: MessageTaskCreating {
    let editing: TasksEditingModel

    func createTask(from draft: MessageTaskDraft) async throws -> MessageTaskCreationResult {
        guard case .providerTaskList(let collectionID) = draft.target.kind
        else {
            throw MessageTaskCreationError.unsupportedTarget
        }
        await editing.load()
        guard let target = await editing.target(for: collectionID) else {
            throw MessageTaskCreationError.unsupportedTarget
        }
        var taskDraft = TaskDraft()
        taskDraft.title = draft.title
        taskDraft.notes = draft.notes
        taskDraft.due = draft.dueDate
        taskDraft.targetID = target.id
        taskDraft.links = [draft.deepLink.absoluteString]
        do {
            _ = try await editing.create(taskDraft)
            return MessageTaskCreationResult(
                message: String(
                    localized: "Task created in \(target.collection.displayName).",
                    bundle: .module
                )
            )
        } catch {
            throw MessageTaskCreationError.providerWriteFailed(
                error.localizedDescription
            )
        }
    }
}
