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
import SwiftUI

/// Compact header text for the phone reader (Apple Mail style): a short,
/// locale-aware date beside the sender and a combined VoiceOver summary.
enum MessageReaderHeaderPresentation {
    /// Short reader date: today shows the time, the previous six days show the
    /// weekday, earlier dates this year show day and month, and older dates
    /// add the year. Future dates (clock skew) never render as a weekday.
    /// - Parameters:
    ///   - date: The message date.
    ///   - now: The reference "current" time.
    ///   - calendar: Calendar used for day arithmetic and formatting.
    ///   - locale: Locale that decides field order, 12/24-hour time and names.
    ///   - timeZone: Zone that decides where the day boundaries fall.
    static func shortDate(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard MessageListDatePresentation.isKnown(date) else {
            return MessageListDatePresentation.unknownDateLabel
        }
        var calendar = calendar
        calendar.timeZone = timeZone
        let base = Date.FormatStyle(
            date: nil,
            time: nil,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        let dayDistance = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch dayDistance {
        case 0:
            return date.formatted(base.hour().minute())
        case 1 ... 6:
            return date.formatted(base.weekday(.abbreviated))
        default:
            if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                return date.formatted(base.month(.abbreviated).day())
            }
            return date.formatted(base.year().month(.abbreviated).day())
        }
    }

    /// Single VoiceOver phrase for the sender line, using the full date so the
    /// abbreviated visual date is not what gets read aloud.
    static func accessibilityLabel(senderName: String, fullDate: String) -> String {
        String(localized: "From \(senderName), \(fullDate)", bundle: .module)
    }
}

private struct MessageReaderReferenceDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// Fixed "now" for the reader header's short date. Nil (the default) uses
    /// the wall clock; snapshot tests pin it so baselines never age.
    var messageReaderReferenceDate: Date? {
        get { self[MessageReaderReferenceDateKey.self] }
        set { self[MessageReaderReferenceDateKey.self] = newValue }
    }
}
