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

/// Copy and destination for the Calendar, Contacts and Tasks empty states.
enum PIMNoSourcesPresentation {
    /// The PIM surface the empty state belongs to.
    enum Kind: CaseIterable {
        case calendar
        case contacts
        case tasks
    }

    /// Title, explanation and action title for one surface.
    struct Copy: Equatable {
        let title: String
        let message: String
        let actionTitle: String
    }

    /// The Settings pane that connects calendar, contacts and task sources.
    static let settingsSection: SettingsSection = .calendarContacts

    /// Returns the copy for the surface showing the empty state.
    static func copy(for kind: Kind) -> Copy {
        switch kind {
        case .calendar:
            Copy(
                title: String(localized: "No Calendars", bundle: .module),
                message: String(
                    localized: "Connect a calendar account to see your events here.",
                    bundle: .module
                ),
                actionTitle: String(localized: "Connect a Calendar…", bundle: .module)
            )
        case .contacts:
            Copy(
                title: String(localized: "No Address Books", bundle: .module),
                message: String(
                    localized: "Connect a contacts account to see people here.",
                    bundle: .module
                ),
                actionTitle: String(localized: "Connect Contacts…", bundle: .module)
            )
        case .tasks:
            Copy(
                title: String(localized: "No Task Lists", bundle: .module),
                message: String(
                    localized: "Connect an account with task lists to see your tasks here.",
                    bundle: .module
                ),
                actionTitle: String(localized: "Connect Task Lists…", bundle: .module)
            )
        }
    }
}
