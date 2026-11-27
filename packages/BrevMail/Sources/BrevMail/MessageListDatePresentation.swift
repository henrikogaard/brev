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
    enum RelativeStyle: Equatable, Sendable {
        case standard
        case compact
    }

    static var unknownDateLabel: String { String(localized: "Unknown date", bundle: .module) }

    static func label(
        for date: Date,
        showsAbsoluteArrivalTime: Bool,
        relativeStyle: RelativeStyle = .standard,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard isKnown(date) else { return unknownDateLabel }

        guard showsAbsoluteArrivalTime else {
            switch relativeStyle {
            case .standard, .compact:
                // Both parent and reply rows show an elapsed age. Foundation's
                // abbreviated directional formatter emits "-3 t" in Norwegian.
                return compactRelativeLabel(
                    for: date,
                    referenceDate: referenceDate,
                    calendar: calendar,
                    locale: locale
                )
            }
        }

        return absoluteLabel(
            for: date,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    /// The spoken form of the row date: "25 minutes ago" rather than "25m" (audit L10).
    /// Absolute arrival times are already readable and stay as they are.
    static func accessibilityLabel(
        for date: Date,
        showsAbsoluteArrivalTime: Bool,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard isKnown(date) else { return unknownDateLabel }
        guard !showsAbsoluteArrivalTime else {
            return absoluteLabel(
                for: date,
                referenceDate: referenceDate,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        }
        return spokenRelativeLabel(
            for: date,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale
        )
    }

    static func spokenRelativeLabel(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let referenceSecond = referenceDate.timeIntervalSinceReferenceDate.rounded(.down)
        let key = spokenRelativeCacheKey(
            for: date,
            referenceSecond: referenceSecond,
            calendar: calendar,
            locale: locale
        )
        formatterLock.lock()
        if let cached = spokenRelativeLabelCache[key] {
            #if DEBUG
            spokenRelativeLabelCacheHitCountsForTesting[key, default: 0] += 1
            #endif
            formatterLock.unlock()
            return cached
        }
        formatterLock.unlock()

        let label = relativeFormatter(locale: locale, calendar: calendar)
            .localizedString(for: date, relativeTo: Date(timeIntervalSinceReferenceDate: referenceSecond))

        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = spokenRelativeLabelCache[key] {
            #if DEBUG
            spokenRelativeLabelCacheHitCountsForTesting[key, default: 0] += 1
            #endif
            return cached
        }
        if spokenRelativeLabelCache.count >= 512 {
            spokenRelativeLabelCache.removeAll(keepingCapacity: true)
            #if DEBUG
            spokenRelativeLabelCacheHitCountsForTesting.removeAll(keepingCapacity: true)
            #endif
        }
        spokenRelativeLabelCache[key] = label
        return label
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

    static func compactRelativeLabel(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let referenceSecond = referenceDate.timeIntervalSinceReferenceDate.rounded(.down)
        let key = compactRelativeCacheKey(
            for: date,
            referenceSecond: referenceSecond,
            calendar: calendar,
            locale: locale
        )
        formatterLock.lock()
        if let cached = compactRelativeLabelCache[key] {
            #if DEBUG
            compactRelativeLabelCacheHitCountsForTesting[key, default: 0] += 1
            #endif
            formatterLock.unlock()
            return cached
        }
        formatterLock.unlock()

        let label = compactRelativeLabelUncached(
            for: date,
            referenceDate: Date(timeIntervalSinceReferenceDate: referenceSecond),
            calendar: calendar,
            locale: locale
        )

        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = compactRelativeLabelCache[key] {
            #if DEBUG
            compactRelativeLabelCacheHitCountsForTesting[key, default: 0] += 1
            #endif
            return cached
        }
        if compactRelativeLabelCache.count >= 512 {
            compactRelativeLabelCache.removeAll(keepingCapacity: true)
            #if DEBUG
            compactRelativeLabelCacheHitCountsForTesting.removeAll(keepingCapacity: true)
            #endif
        }
        compactRelativeLabelCache[key] = label
        return label
    }

    #if DEBUG
    static func compactRelativeLabelCacheHitCountForTesting(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale
    ) -> Int {
        let key = compactRelativeCacheKey(
            for: date,
            referenceSecond: referenceDate.timeIntervalSinceReferenceDate.rounded(.down),
            calendar: calendar,
            locale: locale
        )
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return compactRelativeLabelCacheHitCountsForTesting[key, default: 0]
    }

    static func spokenRelativeLabelCacheHitCountForTesting(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale
    ) -> Int {
        let key = spokenRelativeCacheKey(
            for: date,
            referenceSecond: referenceDate.timeIntervalSinceReferenceDate.rounded(.down),
            calendar: calendar,
            locale: locale
        )
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return spokenRelativeLabelCacheHitCountsForTesting[key, default: 0]
    }
    #endif

    static func compactRelativeLabelUncached(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let elapsed = referenceDate.timeIntervalSince(date)
        // Arrival timestamps should be in the past. Keep the directional
        // formatter for clock skew or scheduled test data so a future value
        // never looks like elapsed time.
        guard elapsed >= 0 else {
            return relativeFormatter(locale: locale, calendar: calendar)
                .localizedString(for: date, relativeTo: referenceDate)
        }
        if elapsed < 1 { return String(localized: "Now", bundle: .module) }
        return compactElapsedFormatter(locale: locale, calendar: calendar)
            .string(from: elapsed)
            ?? relativeFormatter(locale: locale, calendar: calendar)
            .localizedString(for: date, relativeTo: referenceDate)
    }

    // Formatters are expensive to construct and this type is evaluated once per
    // visible row on every list re-render, so configured instances are cached and
    // reused. `DateFormatter`/`RelativeDateTimeFormatter` are safe to read from
    // multiple threads once configured; the cache dictionaries are guarded by a lock.
    private static let formatterLock = NSLock()
    private enum RelativeAgeBucket: Hashable {
        /// Quantized elapsed seconds (1s for <60s, 60s for <1h, 3600s for <24h, 86400s for >=24h).
        case quantizedElapsed(Int64)
        /// Day-quantized pair for multi-week dates where calendar month/year boundaries matter.
        case calendarDays(dateDay: Int64, referenceDay: Int64)
    }

    private struct RelativeLabelCacheKey: Hashable {
        let bucket: RelativeAgeBucket
        let localeIdentifier: String
        let calendarIdentifier: Calendar.Identifier
    }

    private static let calendarMonthThresholdSeconds: TimeInterval = 28 * 86400

    private static func quantizedElapsedBucket(
        dateInterval: TimeInterval,
        referenceSecond: TimeInterval,
        useCalendarDaysForMonths: Bool
    ) -> RelativeAgeBucket {
        let elapsed = referenceSecond - dateInterval
        let absElapsed = abs(elapsed)
        if useCalendarDaysForMonths, absElapsed >= calendarMonthThresholdSeconds {
            let dateDay = Int64((dateInterval / 86400).rounded(.down))
            let referenceDay = Int64((referenceSecond / 86400).rounded(.down))
            return .calendarDays(dateDay: dateDay, referenceDay: referenceDay)
        }
        let step: TimeInterval
        if absElapsed < 60 {
            step = 1
        } else if absElapsed < 3600 {
            step = 60
        } else if absElapsed < 86400 {
            step = 3600
        } else {
            step = 86400
        }
        let quantized = (absElapsed / step).rounded(.down) * step
        return .quantizedElapsed(elapsed < 0 ? -Int64(quantized) : Int64(quantized))
    }

    private static func compactRelativeCacheKey(
        for date: Date,
        referenceSecond: TimeInterval,
        calendar: Calendar,
        locale: Locale
    ) -> RelativeLabelCacheKey {
        let dateInterval = date.timeIntervalSinceReferenceDate
        let isFuture = referenceSecond - dateInterval < 0
        return RelativeLabelCacheKey(
            bucket: quantizedElapsedBucket(
                dateInterval: dateInterval,
                referenceSecond: referenceSecond,
                useCalendarDaysForMonths: isFuture
            ),
            localeIdentifier: locale.identifier,
            calendarIdentifier: calendar.identifier
        )
    }

    private static func spokenRelativeCacheKey(
        for date: Date,
        referenceSecond: TimeInterval,
        calendar: Calendar,
        locale: Locale
    ) -> RelativeLabelCacheKey {
        RelativeLabelCacheKey(
            bucket: quantizedElapsedBucket(
                dateInterval: date.timeIntervalSinceReferenceDate,
                referenceSecond: referenceSecond,
                useCalendarDaysForMonths: true
            ),
            localeIdentifier: locale.identifier,
            calendarIdentifier: calendar.identifier
        )
    }

    private nonisolated(unsafe) static var compactRelativeLabelCache: [RelativeLabelCacheKey: String] = [:]
    private nonisolated(unsafe) static var spokenRelativeLabelCache: [RelativeLabelCacheKey: String] = [:]
    #if DEBUG
    private nonisolated(unsafe) static var compactRelativeLabelCacheHitCountsForTesting: [RelativeLabelCacheKey: Int] = [:]
    private nonisolated(unsafe) static var spokenRelativeLabelCacheHitCountsForTesting: [RelativeLabelCacheKey: Int] = [:]
    #endif
    private nonisolated(unsafe) static var dateFormatterCache: [String: DateFormatter] = [:]
    private nonisolated(unsafe) static var relativeFormatterCache: [String: RelativeDateTimeFormatter] = [:]
    private nonisolated(unsafe) static var compactElapsedFormatterCache: [String: DateComponentsFormatter] = [:]

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
        formatter.unitsStyle = .full
        formatter.locale = locale
        formatter.calendar = calendar
        relativeFormatterCache[key] = formatter
        return formatter
    }

    private static func compactElapsedFormatter(
        locale: Locale,
        calendar: Calendar
    ) -> DateComponentsFormatter {
        let key = "\(locale.identifier)|\(calendar.identifier)"
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = compactElapsedFormatterCache[key] { return cached }
        let formatter = DateComponentsFormatter()
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        formatter.calendar = localizedCalendar
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        compactElapsedFormatterCache[key] = formatter
        return formatter
    }
}
