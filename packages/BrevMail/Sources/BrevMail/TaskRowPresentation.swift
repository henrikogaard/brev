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

/// Accessibility text for a task row (audit finding P4).
///
/// The row exposes two elements: a text element that speaks the title,
/// notes, due date and "Overdue", and the completion toggle, labelled
/// "Completed" with Yes or No as its value.
enum TaskRowPresentation {
    /// Smallest touch target for the completion toggle, in points.
    static let minimumToggleSize: CGFloat = 44

    /// The toggle's label.
    static func toggleLabel() -> String {
        String(localized: "Completed", bundle: .module)
    }

    /// The toggle's value: "Yes" when the task is completed, otherwise "No".
    static func toggleValue(for task: PIMTask) -> String {
        task.isCompleted
            ? String(localized: "Yes", bundle: .module)
            : String(localized: "No", bundle: .module)
    }

    /// Whether the due date has passed on a task that is still open.
    static func isOverdue(_ task: PIMTask, now: Date) -> Bool {
        guard let due = task.due, !task.isCompleted else { return false }
        return due < now
    }

    /// The word shown (and spoken) next to an overdue date.
    static func overdueText() -> String {
        String(localized: "Overdue", bundle: .module)
    }

    /// Title, notes, due date and "Overdue", comma-joined.
    static func rowLabel(for task: PIMTask, now: Date, calendar: Calendar) -> String {
        var parts = [task.title ?? String(localized: "Untitled task", bundle: .module)]
        if let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes)
        }
        if let due = task.due {
            parts.append(String(localized: "Due \(dueText(due, calendar: calendar))", bundle: .module))
        }
        if isOverdue(task, now: now) {
            parts.append(overdueText())
        }
        return parts.joined(separator: ", ")
    }

    /// The abbreviated due date shown in the row.
    static func dueText(_ due: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .current
        return due.formatted(style)
    }
}
