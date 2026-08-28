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
#if canImport(EventKit)
@preconcurrency import EventKit
#endif

enum MessageTaskCreationTarget: String, CaseIterable, Equatable, Sendable {
    case appleReminders
    case systemShare

    var title: String {
        switch self {
        case .appleReminders: return "Reminders"
        case .systemShare: return "Share"
        }
    }
}

struct MessageTaskDraft: Equatable, Sendable {
    var title: String
    var notes: String
    var dueDate: Date?
    var deepLink: URL
    var target: MessageTaskCreationTarget

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

    var errorDescription: String? {
        switch self {
        case .remindersUnavailable:
            String(localized: "Apple Reminders is unavailable.", bundle: .module)
        case .remindersAccessDenied:
            String(localized: "Brev does not have permission to create reminders.", bundle: .module)
        case .unsupportedTarget:
            String(localized: "This task handoff target is unavailable.", bundle: .module)
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
        target: MessageTaskCreationTarget = .appleReminders
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
        guard draft.target == .appleReminders else {
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
