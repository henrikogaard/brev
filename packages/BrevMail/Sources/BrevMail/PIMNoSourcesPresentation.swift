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

import BrevSettings
import Foundation

/// Copy and destination for the Calendar, Contacts and Tasks "nothing is
/// connected" empty state (audit finding P1).
///
/// All three surfaces are fed by the same Settings pane, so they share one
/// destination and one button title; only the sentence differs per surface.
enum PIMNoSourcesPresentation {
    /// The PIM surface the empty state belongs to.
    enum Kind: CaseIterable {
        case calendar
        case contacts
        case tasks
    }

    /// Title, explanation and button title for one surface.
    struct Copy: Equatable {
        let title: String
        let message: String
        let actionTitle: String
    }

    /// The Settings pane that connects calendar, contacts and task sources.
    static let settingsSection: SettingsSection = .calendarContacts

    /// - Parameters:
    ///   - kind: The surface showing the empty state.
    ///   - usesCategorySettings: True when Settings shows the category sidebar
    ///     (regular width), where the pane sits under "Accounts & Connections".
    ///     Compact Settings lists the pane directly.
    static func copy(for kind: Kind, usesCategorySettings: Bool) -> Copy {
        Copy(
            title: title(for: kind),
            message: message(for: kind, usesCategorySettings: usesCategorySettings),
            actionTitle: String(localized: "Open Calendar & Contacts Settings", bundle: .module)
        )
    }

    private static func title(for kind: Kind) -> String {
        switch kind {
        case .calendar:
            String(localized: "No calendars connected", bundle: .module)
        case .contacts:
            String(localized: "No contacts sources connected", bundle: .module)
        case .tasks:
            String(localized: "No tasks sources connected", bundle: .module)
        }
    }

    private static func message(for kind: Kind, usesCategorySettings: Bool) -> String {
        switch (kind, usesCategorySettings) {
        case (.calendar, false):
            String(
                localized: "Connect a calendar in Settings → Calendar & Contacts to see events here.",
                bundle: .module
            )
        case (.calendar, true):
            String(
                localized:
                "Connect a calendar in Settings → Accounts & Connections → Calendar & Contacts to see events here.",
                bundle: .module
            )
        case (.contacts, false):
            String(
                localized: "Connect a contacts source in Settings → Calendar & Contacts to see people here.",
                bundle: .module
            )
        case (.contacts, true):
            String(
                localized:
                "Connect a contacts source in Settings → Accounts & Connections → Calendar & Contacts to see people here.",
                bundle: .module
            )
        case (.tasks, false):
            String(
                localized: "Connect a tasks source in Settings → Calendar & Contacts to see tasks here.",
                bundle: .module
            )
        case (.tasks, true):
            String(
                localized:
                "Connect a tasks source in Settings → Accounts & Connections → Calendar & Contacts to see tasks here.",
                bundle: .module
            )
        }
    }
}
