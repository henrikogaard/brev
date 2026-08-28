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

/// An editable calendar-event draft derived from a message ("Create Meeting
/// from Message", #268). The user confirms/edits it before it is written to the
/// system calendar via EventKit — a one-off local handoff, mirroring the
/// Create Task → Reminders flow. Brev does not become a calendar client
/// (ADR-0007): no sync, no browsing, write-only on explicit user action.
struct MessageEventDraft: Equatable, Sendable {
    var title: String
    var notes: String
    var startDate: Date
    var endDate: Date
    /// Attendee email addresses (sender + recipients). Surfaced in the notes —
    /// EventKit's attendee list is read-only through the public API.
    var attendees: [String]
    var deepLink: URL

    var isCreateEnabled: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && endDate >= startDate
    }
}

struct MessageEventCreationResult: Equatable, Sendable {
    let message: String
}

protocol MessageEventCreating {
    func createEvent(from draft: MessageEventDraft) async throws -> MessageEventCreationResult
}

enum MessageEventCreationError: LocalizedError, Equatable {
    case calendarsUnavailable
    case calendarsAccessDenied

    var errorDescription: String? {
        switch self {
        case .calendarsUnavailable:
            String(localized: "Apple Calendar is unavailable.", bundle: .module)
        case .calendarsAccessDenied:
            String(localized: "Brev does not have permission to create calendar events.", bundle: .module)
        }
    }
}

enum MessageEventDraftBuilder {
    /// Reused formatter for the "Received" notes line; `ISO8601DateFormatter` is
    /// thread-safe for formatting, so a single shared instance avoids allocating
    /// one per draft.
    private static let receivedDateFormatter = ISO8601DateFormatter()

    /// Builds an event draft from a message. The start defaults to
    /// `referenceDate` for a `defaultDuration`-long event; the user adjusts the
    /// time in the editor. Attendees are the deduplicated sender + recipients.
    static func draft(
        for header: MessageHeader,
        accountID: String,
        referenceDate: Date,
        defaultDuration: TimeInterval = 3600
    ) -> MessageEventDraft? {
        guard let deepLink = MessageTaskDeepLinkBuilder.url(for: header, accountID: accountID) else {
            return nil
        }
        let attendees = attendees(for: header)
        return MessageEventDraft(
            title: title(for: header),
            notes: notes(for: header, attendees: attendees, deepLink: deepLink),
            startDate: referenceDate,
            endDate: referenceDate.addingTimeInterval(defaultDuration),
            attendees: attendees,
            deepLink: deepLink
        )
    }

    static func title(for header: MessageHeader) -> String {
        let subject = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "Meeting about email from \(header.from.displayName)" : subject
    }

    /// Sender + To + Cc emails, deduplicated case-insensitively, order preserved.
    static func attendees(for header: MessageHeader) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for correspondent in [header.from] + header.to + header.cc {
            let email = correspondent.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, seen.insert(email.lowercased()).inserted else { continue }
            result.append(email)
        }
        return result
    }

    private static func notes(for header: MessageHeader, attendees: [String], deepLink: URL) -> String {
        let subject = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            attendees.isEmpty ? nil : "Attendees: \(attendees.joined(separator: ", "))",
            subject.isEmpty ? nil : "Subject: \(subject)",
            "Received: \(receivedDateFormatter.string(from: header.date))",
            "Brev link: \(deepLink.absoluteString)",
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

#if canImport(EventKit)
final class AppleCalendarEventCreator: MessageEventCreating {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func createEvent(from draft: MessageEventDraft) async throws -> MessageEventCreationResult {
        let granted = try await eventStore.requestFullAccessToEvents()
        guard granted else {
            throw MessageEventCreationError.calendarsAccessDenied
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw MessageEventCreationError.calendarsUnavailable
        }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        try eventStore.save(event, span: .thisEvent, commit: true)
        return MessageEventCreationResult(message: String(localized: "Event created in Calendar.", bundle: .module))
    }
}
#else
struct AppleCalendarEventCreator: MessageEventCreating {
    func createEvent(from _: MessageEventDraft) async throws -> MessageEventCreationResult {
        throw MessageEventCreationError.calendarsUnavailable
    }
}
#endif
