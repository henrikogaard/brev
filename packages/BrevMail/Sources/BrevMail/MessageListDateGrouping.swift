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

struct MessageListDateSection: Identifiable, Equatable {
    let title: String
    let headers: [MessageHeader]

    var id: String { title }
}

enum MessageListDateGrouping {
    static func sections(
        for headers: [MessageHeader],
        pinnedIDs: Set<MessageHeader.ID> = [],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [MessageListDateSection] {
        var sections: [MessageListDateSection] = []
        let pinned = headers.filter { pinnedIDs.contains($0.id) }
        if !pinned.isEmpty {
            sections.append(MessageListDateSection(
                title: String(localized: "Pinned", bundle: .module),
                headers: pinned
            ))
        }

        var currentTitle: String?
        var currentHeaders: [MessageHeader] = []
        for header in headers where !pinnedIDs.contains(header.id) {
            let title = sectionTitle(for: header.date, referenceDate: referenceDate, calendar: calendar)
            if currentTitle == title {
                currentHeaders.append(header)
            } else {
                appendSection(title: currentTitle, headers: currentHeaders, to: &sections)
                currentTitle = title
                currentHeaders = [header]
            }
        }
        appendSection(title: currentTitle, headers: currentHeaders, to: &sections)
        return sections
    }

    private static func appendSection(
        title: String?,
        headers: [MessageHeader],
        to sections: inout [MessageListDateSection]
    ) {
        guard let title, !headers.isEmpty else { return }
        sections.append(MessageListDateSection(title: title, headers: headers))
    }

    static func sectionTitle(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return String(localized: "Today", bundle: .module)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday", bundle: .module)
        }

        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        let startOfMessageDay = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: startOfMessageDay, to: startOfReferenceDay).day ?? 0

        switch dayDelta {
        case ..<0:
            return String(localized: "Future", bundle: .module)
        case 2 ... 6:
            return String(localized: "This week", bundle: .module)
        case 7 ... 13:
            return String(localized: "Last week", bundle: .module)
        case 14 ... 29:
            return String(localized: "Two weeks ago", bundle: .module)
        default:
            return monthTitle(for: date, referenceDate: referenceDate, calendar: calendar)
        }
    }

    private static func monthTitle(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let startOfReferenceMonth = monthStart(for: referenceDate, calendar: calendar)
        let startOfMessageMonth = monthStart(for: date, calendar: calendar)
        let monthDelta = calendar.dateComponents([.month], from: startOfMessageMonth, to: startOfReferenceMonth).month ?? 0

        switch monthDelta {
        case ..<0:
            return String(localized: "Future", bundle: .module)
        case 0:
            return String(localized: "Earlier this month", bundle: .module)
        case 1:
            return String(localized: "One month ago", bundle: .module)
        case 2 ... 11:
            return String(localized: "\(monthDelta) months ago", bundle: .module)
        default:
            // Past a year, group by years rather than showing absurd month
            // counts like "164 months ago".
            let years = monthDelta / 12
            return years == 1
                ? String(localized: "One year ago", bundle: .module)
                : String(localized: "\(years) years ago", bundle: .module)
        }
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
