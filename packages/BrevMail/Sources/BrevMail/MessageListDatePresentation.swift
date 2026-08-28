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

enum MessageListDatePresentation {
    static let unknownDateLabel = "Unknown date"

    static func label(
        for date: Date,
        showsAbsoluteArrivalTime: Bool,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard isKnown(date) else { return unknownDateLabel }

        guard showsAbsoluteArrivalTime else {
            return relativeFormatter(locale: locale, calendar: calendar)
                .localizedString(for: date, relativeTo: referenceDate)
        }

        return absoluteLabel(
            for: date,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    static func isKnown(_ date: Date) -> Bool {
        date != Date.distantPast
    }

    private static func absoluteLabel(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let time = formatted(date, template: "jm", calendar: calendar, locale: locale, timeZone: timeZone)
        guard !calendar.isDate(date, inSameDayAs: referenceDate) else { return time }

        let dateTemplate = calendar.isDate(date, equalTo: referenceDate, toGranularity: .year)
            ? "MMM d"
            : "MMM d y"
        let day = formatted(date, template: dateTemplate, calendar: calendar, locale: locale, timeZone: timeZone)
        return "\(day), \(time)"
    }

    private static func formatted(
        _ date: Date,
        template: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        dateFormatter(template: template, calendar: calendar, locale: locale, timeZone: timeZone)
            .string(from: date)
    }

    // Formatters are expensive to construct and this type is evaluated once per
    // visible row on every list re-render, so configured instances are cached and
    // reused. `DateFormatter`/`RelativeDateTimeFormatter` are safe to read from
    // multiple threads once configured; the cache dictionaries are guarded by a lock.
    private static let formatterLock = NSLock()
    private nonisolated(unsafe) static var dateFormatterCache: [String: DateFormatter] = [:]
    private nonisolated(unsafe) static var relativeFormatterCache: [String: RelativeDateTimeFormatter] = [:]

    private static func dateFormatter(
        template: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(timeZone.identifier)|\(calendar.identifier)"
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = dateFormatterCache[key] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: template,
            options: 0,
            locale: locale
        )?.replacingOccurrences(of: "\u{202F}", with: " ") ?? template
        dateFormatterCache[key] = formatter
        return formatter
    }

    private static func relativeFormatter(locale: Locale, calendar: Calendar) -> RelativeDateTimeFormatter {
        let key = "\(locale.identifier)|\(calendar.identifier)"
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = relativeFormatterCache[key] { return cached }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        formatter.calendar = calendar
        relativeFormatterCache[key] = formatter
        return formatter
    }
}
