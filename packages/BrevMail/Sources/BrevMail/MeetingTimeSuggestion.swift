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

enum MeetingWeekday: Int, CaseIterable, Codable, Sendable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
}

struct MeetingTimeSuggestionSettings: Equatable, Sendable {
    enum Key {
        static let isEnabled = "compose.meetingSuggestions.isEnabled"
        static let localAvailabilitySourceEnabled = "compose.meetingSuggestions.localAvailabilitySourceEnabled"
        static let workdayStartMinute = "compose.meetingSuggestions.workdayStartMinute"
        static let workdayEndMinute = "compose.meetingSuggestions.workdayEndMinute"
        static let timeZoneIdentifier = "compose.meetingSuggestions.timeZoneIdentifier"
    }

    static let localAvailabilitySourceID = "local-availability"
    static let defaultWorkingDays: Set<MeetingWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let defaultWorkdayStartMinute = 9 * 60
    static let defaultWorkdayEndMinute = 17 * 60

    var isEnabled: Bool
    var workingDays: Set<MeetingWeekday>
    var workdayStartMinute: Int
    var workdayEndMinute: Int
    var timeZoneIdentifier: String
    var enabledAvailabilitySourceIDs: Set<String>

    init(
        isEnabled: Bool,
        workingDays: Set<MeetingWeekday>,
        workdayStartMinute: Int,
        workdayEndMinute: Int,
        timeZoneIdentifier: String,
        enabledAvailabilitySourceIDs: Set<String>
    ) {
        self.isEnabled = isEnabled
        self.workingDays = workingDays
        self.workdayStartMinute = workdayStartMinute
        self.workdayEndMinute = workdayEndMinute
        self.timeZoneIdentifier = timeZoneIdentifier
        self.enabledAvailabilitySourceIDs = enabledAvailabilitySourceIDs
    }
}

struct MeetingBusyInterval: Equatable, Sendable {
    let sourceID: String
    let start: Date
    let end: Date
}

struct MeetingTimeSuggestionSlot: Equatable, Sendable {
    let start: Date
    let end: Date
}

enum MeetingTimeSuggestionUnavailableReason: Equatable, Sendable {
    case disabled
    case noAvailabilitySourcesEnabled
    case invalidTimeZone
    case invalidWorkingHours
    case noWorkingDays
    case noAvailableTimes

    var message: String {
        switch self {
        case .disabled:
            return "Meeting-time suggestions are disabled. Enable them in Settings first."
        case .noAvailabilitySourcesEnabled:
            return "Enable at least one availability source in Settings before suggesting meeting times."
        case .invalidTimeZone:
            return "The meeting-time timezone setting is invalid. Update it in Settings."
        case .invalidWorkingHours:
            return "Meeting-time working hours need a start time before the end time."
        case .noWorkingDays:
            return "Choose at least one working day before suggesting meeting times."
        case .noAvailableTimes:
            return "No available meeting times were found inside the configured working hours."
        }
    }
}

struct MeetingTimeSuggestionResult: Equatable, Sendable {
    let slots: [MeetingTimeSuggestionSlot]?
    let unavailableReason: MeetingTimeSuggestionUnavailableReason?
    let timeZone: TimeZone?
    let requiresExternalCall: Bool

    static func unavailable(_ reason: MeetingTimeSuggestionUnavailableReason) -> MeetingTimeSuggestionResult {
        MeetingTimeSuggestionResult(
            slots: nil,
            unavailableReason: reason,
            timeZone: nil,
            requiresExternalCall: false
        )
    }

    static func available(
        slots: [MeetingTimeSuggestionSlot],
        timeZone: TimeZone
    ) -> MeetingTimeSuggestionResult {
        MeetingTimeSuggestionResult(
            slots: slots,
            unavailableReason: nil,
            timeZone: timeZone,
            requiresExternalCall: false
        )
    }
}

enum MeetingTimeSuggestionPolicy {
    static func suggestions(
        settings: MeetingTimeSuggestionSettings,
        busyIntervals: [MeetingBusyInterval],
        now: Date = Date(),
        durationMinutes: Int = 30,
        count: Int = 3,
        searchDayLimit: Int = 14
    ) -> MeetingTimeSuggestionResult {
        guard settings.isEnabled else {
            return .unavailable(.disabled)
        }
        guard !settings.enabledAvailabilitySourceIDs.isEmpty else {
            return .unavailable(.noAvailabilitySourcesEnabled)
        }
        guard let timeZone = TimeZone(identifier: settings.timeZoneIdentifier) else {
            return .unavailable(.invalidTimeZone)
        }
        guard settings.workdayStartMinute >= 0,
              settings.workdayEndMinute <= 24 * 60,
              settings.workdayStartMinute < settings.workdayEndMinute else {
            return .unavailable(.invalidWorkingHours)
        }
        guard !settings.workingDays.isEmpty else {
            return .unavailable(.noWorkingDays)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let enabledBusyIntervals = busyIntervals.filter {
            settings.enabledAvailabilitySourceIDs.contains($0.sourceID) && $0.start < $0.end
        }
        let duration = TimeInterval(max(1, durationMinutes) * 60)
        let step = TimeInterval(30 * 60)
        var slots: [MeetingTimeSuggestionSlot] = []

        for dayOffset in 0 ..< max(1, searchDayLimit) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else {
                continue
            }
            let weekdayValue = calendar.component(.weekday, from: day)
            guard let weekday = MeetingWeekday(rawValue: weekdayValue),
                  settings.workingDays.contains(weekday),
                  let workdayStart = date(on: day, minuteOfDay: settings.workdayStartMinute, calendar: calendar),
                  let workdayEnd = date(on: day, minuteOfDay: settings.workdayEndMinute, calendar: calendar) else {
                continue
            }

            var candidate = roundedUpToStep(max(now, workdayStart), step: step, calendar: calendar)
            while candidate.addingTimeInterval(duration) <= workdayEnd {
                let slot = MeetingTimeSuggestionSlot(
                    start: candidate,
                    end: candidate.addingTimeInterval(duration)
                )
                if !enabledBusyIntervals.contains(where: { overlaps(slot, $0) }) {
                    slots.append(slot)
                    if slots.count >= count {
                        return .available(slots: slots, timeZone: timeZone)
                    }
                }
                candidate = candidate.addingTimeInterval(step)
            }
        }

        return slots.isEmpty ? .unavailable(.noAvailableTimes) : .available(slots: slots, timeZone: timeZone)
    }

    private static func date(on day: Date, minuteOfDay: Int, calendar: Calendar) -> Date? {
        calendar.date(
            byAdding: .minute,
            value: minuteOfDay,
            to: calendar.startOfDay(for: day)
        )
    }

    private static func roundedUpToStep(_ date: Date, step: TimeInterval, calendar: Calendar) -> Date {
        let secondsFromStartOfDay = date.timeIntervalSince(calendar.startOfDay(for: date))
        let roundedSeconds = (secondsFromStartOfDay / step).rounded(.up) * step
        return calendar.startOfDay(for: date).addingTimeInterval(roundedSeconds)
    }

    private static func overlaps(_ slot: MeetingTimeSuggestionSlot, _ busy: MeetingBusyInterval) -> Bool {
        slot.start < busy.end && busy.start < slot.end
    }
}

enum MeetingTimeSuggestionFormatter {
    static func editableText(
        for slots: [MeetingTimeSuggestionSlot],
        timeZone: TimeZone
    ) -> String {
        let lines = slots.map { slot in
            "- \(dateFormatter(timeZone: timeZone).string(from: slot.start)), \(timeFormatter(timeZone: timeZone).string(from: slot.start))-\(timeFormatter(timeZone: timeZone).string(from: slot.end)) \(timeZone.identifier)"
        }
        return (["Here are a few times that work for me:"] + lines).joined(separator: "\n")
    }

    static func settingsTimeLabel(minutes: Int) -> String {
        let hour = max(0, min(23, minutes / 60))
        let minute = max(0, min(59, minutes % 60))
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }

    private static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}

struct MeetingTimeSuggestionInsertion: Equatable, Sendable {
    let body: String
    let shouldSend: Bool
    let isEditable: Bool

    static func insert(
        _ text: String,
        into body: String,
        selection: ComposeBodyTextSelection?,
        insertionPoint: ComposeBodyInsertionPoint?
    ) -> MeetingTimeSuggestionInsertion {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedBody: String
        if let selection, let replaced = selection.replacingSelection(in: body, with: trimmedText) {
            updatedBody = replaced
        } else if let insertionPoint, let inserted = insertionPoint.insertingText(
            insertionText(trimmedText, atCursorIn: body),
            in: body
        ) {
            updatedBody = inserted
        } else if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedBody = trimmedText
        } else {
            updatedBody = body + "\n\n" + trimmedText
        }

        return MeetingTimeSuggestionInsertion(
            body: updatedBody,
            shouldSend: false,
            isEditable: true
        )
    }

    private static func insertionText(_ text: String, atCursorIn body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : "\n\n\(text)"
    }
}
