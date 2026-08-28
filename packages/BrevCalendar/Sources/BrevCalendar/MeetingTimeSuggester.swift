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

// MARK: - Meeting-time suggestions (#182)

/// A window during which the sender has said they are free. Availability is
/// always *explicit* — provided by the user (or, later, a calendar the user
/// connected) — never inferred without consent (ADR-0006 / ADR-0028 #6).
public struct MeetingAvailabilityWindow: Sendable, Hashable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// A concrete proposed meeting slot.
public struct MeetingTimeSlot: Sendable, Hashable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Proposes meeting times from explicit availability windows. Pure and local —
/// the optional AI phrasing of the resulting text is a separate, user-initiated
/// step; this core needs no network and is fully deterministic.
public enum MeetingTimeSuggester {
    /// Slices `availability` into `duration`-long slots aligned to `granularity`
    /// boundaries, earliest first, returning at most `maxSuggestions`.
    ///
    /// - Parameters:
    ///   - duration: Meeting length in seconds (e.g. 1800 for 30 minutes).
    ///   - granularity: Slot start alignment in seconds (default 30 minutes).
    public static func suggest(
        availability: [MeetingAvailabilityWindow],
        duration: TimeInterval,
        maxSuggestions: Int = 3,
        granularity: TimeInterval = 1800
    ) -> [MeetingTimeSlot] {
        guard duration > 0, granularity > 0, maxSuggestions > 0 else { return [] }

        var slots: [MeetingTimeSlot] = []
        let windows = availability.sorted { $0.start < $1.start }
        for window in windows {
            let windowEnd = window.end.timeIntervalSince1970
            // Align the first candidate start up to the next granularity boundary.
            let startEpoch = window.start.timeIntervalSince1970
            var t = (startEpoch / granularity).rounded(.up) * granularity
            while t + duration <= windowEnd {
                slots.append(
                    MeetingTimeSlot(
                        start: Date(timeIntervalSince1970: t),
                        end: Date(timeIntervalSince1970: t + duration)
                    )
                )
                if slots.count >= maxSuggestions { return slots }
                t += granularity
            }
        }
        return slots
    }

    /// Renders slots as a bulleted list suitable for pasting into a message,
    /// e.g. `- Monday, June 15 at 2:00 PM – 2:30 PM`. Deterministic for a fixed
    /// `timeZone`/`locale`.
    public static func format(
        _ slots: [MeetingTimeSlot],
        timeZone: TimeZone,
        locale: Locale = Locale(identifier: "en_US")
    ) -> String {
        guard !slots.isEmpty else { return "" }
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = timeZone
        day.dateFormat = "EEEE, MMMM d"

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateFormat = "h:mm a"

        return slots.map { slot in
            "- \(day.string(from: slot.start)) at "
                + "\(time.string(from: slot.start)) – \(time.string(from: slot.end))"
        }.joined(separator: "\n")
    }
}
