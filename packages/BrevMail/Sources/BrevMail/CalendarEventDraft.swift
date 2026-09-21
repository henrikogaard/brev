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

import BrevCalendar
import Foundation

/// Editable form state for the calendar event editor (ADR-0072 #7).
///
/// The draft owns every field the editor renders and converts to and
/// from PIMEvent. Provider identity fields (uid, providerItemKey,
/// providerVersion, recurrenceID, rawPayload, organizer, conferenceURL)
/// ride along untouched so an edit round-trips the record the provider
/// owns while the user-facing fields carry the edits.
public struct CalendarEventDraft: Sendable, Hashable {
    /// How often the event repeats in the editor.
    public enum RepeatFrequency: String, CaseIterable, Sendable {
        case never
        case daily
        case weekly
        case monthly
        case yearly

        /// The picker label for the frequency.
        public var title: String {
            switch self {
            case .never:
                String(localized: "Never", bundle: .module)
            case .daily:
                String(localized: "Daily", bundle: .module)
            case .weekly:
                String(localized: "Weekly", bundle: .module)
            case .monthly:
                String(localized: "Monthly", bundle: .module)
            case .yearly:
                String(localized: "Yearly", bundle: .module)
            }
        }
    }

    /// How a repeating series ends.
    public enum RepeatEnd: String, CaseIterable, Sendable {
        case never
        case onDate
        case afterCount

        /// The picker label for the end mode.
        public var title: String {
            switch self {
            case .never:
                String(localized: "Never", bundle: .module)
            case .onDate:
                String(localized: "On date", bundle: .module)
            case .afterCount:
                String(localized: "After count", bundle: .module)
            }
        }
    }

    public var summary = ""
    public var isAllDay = false
    public var start: Date
    public var end: Date
    /// IANA zone identifier; empty means floating/local time.
    public var timeZoneIdentifier = ""
    public var location = ""
    public var notes = ""
    public var status: PIMEventStatus = .confirmed
    public var repeatFrequency: RepeatFrequency = .never
    /// Interval between recurrences; ignored when frequency is never.
    public var repeatInterval = 1
    /// Weekdays for weekly repeats; empty means the start day.
    public var repeatWeekdays: Set<ICSParser.Weekday> = []
    public var repeatEnd: RepeatEnd = .never
    public var repeatUntil: Date
    public var repeatCount = 10
    /// Reminder offsets in minutes before the event.
    public var reminderMinutes: [Int] = []
    /// Attendee email addresses, normalized on commit.
    public var attendeeEmails: [String] = []
    /// The collection the event belongs to after saving — create picks
    /// the target; an edit with a different target moves the event.
    public var targetCollectionID: PIMCollection.ID?

    // Provider identity carried through edits; always nil on create.
    var uid: String?
    var providerItemKey: String?
    var providerVersion: String?
    var recurrenceID: Date?
    var rawPayload: String?
    var organizer: PIMEventPerson?
    var attendeesWithRSVP: [PIMEventPerson] = []
    var conferenceURL: String?
    /// The event's synced conference, preserved across edits (#13).
    var conference: PIMConference?
    /// Editor intent: create a provider conference on save. Only
    /// meaningful for providers that can create conferences (Google);
    /// the write service drops it elsewhere.
    public var requestsConference = false
    var providerUpdatedAt: Date?
    /// The collection the edited event came from; equal to
    /// targetCollectionID unless the user moves the event.
    var originalCollectionID: PIMCollection.ID?

    /// A blank draft for a new event anchored at start.
    public init(start: Date, duration: TimeInterval = 3600) {
        self.start = start
        end = start.addingTimeInterval(duration)
        repeatUntil = start
    }

    /// A draft pre-filled from a cached event for editing.
    public init(event: PIMEvent) {
        summary = event.summary ?? ""
        isAllDay = event.isAllDay
        let fallbackStart = event.start ?? Date()
        start = fallbackStart
        end = event.end ?? fallbackStart.addingTimeInterval(3600)
        timeZoneIdentifier = event.timeZoneIdentifier ?? ""
        location = event.location ?? ""
        notes = event.eventDescription ?? ""
        status = event.status
        reminderMinutes = event.reminders.compactMap(\.minutesBefore)
        attendeeEmails = event.attendees.map(\.email)
        targetCollectionID = event.collectionID
        originalCollectionID = event.collectionID
        repeatUntil = fallbackStart
        if let rule = event.recurrenceRule {
            repeatFrequency = switch rule.frequency {
            case .daily: .daily
            case .weekly: .weekly
            case .monthly: .monthly
            case .yearly: .yearly
            }
            repeatInterval = rule.interval
            repeatWeekdays = Set(rule.byDay ?? [])
            if let count = rule.count {
                repeatEnd = .afterCount
                repeatCount = count
            } else if let until = rule.until {
                repeatEnd = .onDate
                repeatUntil = until
            }
        }
        uid = event.uid
        providerItemKey = event.providerItemKey
        providerVersion = event.providerVersion
        recurrenceID = event.recurrenceID
        rawPayload = event.rawPayload
        organizer = event.organizer
        attendeesWithRSVP = event.attendees
        conferenceURL = event.conferenceURL
        conference = event.conference
        providerUpdatedAt = event.providerUpdatedAt
    }

    /// Whether the required fields hold: a title and a sane range.
    public var isValid: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && end >= start
            && (repeatEnd != .onDate || repeatUntil >= start)
            && (repeatEnd != .afterCount || repeatCount > 0)
    }

    /// Whether this draft edits an existing cached event.
    public var isEditing: Bool { providerItemKey != nil }

    /// Whether the draft describes a repeating series.
    public var repeats: Bool { repeatFrequency != .never }

    /// The RRULE the form describes, or nil when it never repeats.
    public var recurrenceRule: ICSParser.RecurrenceRule? {
        guard repeatFrequency != .never else { return nil }
        let frequency: ICSParser.Frequency = switch repeatFrequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        case .never: .daily // unreachable — guarded above
        }
        var byDay: [ICSParser.Weekday]?
        if repeatFrequency == .weekly {
            let days = repeatWeekdays.sorted { $0.rawValue < $1.rawValue }
            byDay = days.isEmpty ? nil : days
        }
        var count: Int?
        var until: Date?
        switch repeatEnd {
        case .never: break
        case .onDate: until = repeatUntil
        case .afterCount: count = repeatCount
        }
        return ICSParser.RecurrenceRule(
            frequency: frequency,
            interval: max(1, repeatInterval),
            count: count,
            until: until,
            byDay: byDay
        )
    }

    /// Builds the provider-facing event record for a target collection.
    /// Identity fields come from the edited event; on create they stay
    /// nil so the write service assigns them.
    public func makeEvent(
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) -> PIMEvent {
        let attendees = attendeeEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { email -> PIMEventPerson in
                // Preserve the RSVP state of an attendee who was already
                // on the event; new attendees start at needsAction.
                attendeesWithRSVP.first {
                    $0.email.caseInsensitiveCompare(email) == .orderedSame
                } ?? PIMEventPerson(email: email, rsvp: .needsAction)
            }
        return PIMEvent(
            id: PIMEvent.makeID(
                collectionID: collectionID,
                providerItemKey: providerItemKey ?? "draft",
                recurrenceID: recurrenceID
            ),
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: providerItemKey ?? "draft",
            providerVersion: providerVersion,
            uid: uid,
            summary: summary.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            eventDescription: notes.isEmpty ? nil : notes,
            location: location.isEmpty ? nil : location,
            start: start,
            end: end,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier.isEmpty
                ? nil
                : timeZoneIdentifier,
            status: status,
            organizer: organizer,
            attendees: attendees,
            reminders: reminderMinutes.map {
                PIMEventReminder(minutesBefore: $0, method: .alert)
            },
            conferenceURL: conferenceURL,
            conference: conference
                ?? (requestsConference
                    ? PIMConference(
                        kind: .meet,
                        status: .pending,
                        isCreationRequest: true
                    )
                    : nil),
            recurrenceRule: recurrenceRule,
            recurrenceID: recurrenceID,
            rawPayload: rawPayload,
            providerUpdatedAt: providerUpdatedAt
        )
    }
}
