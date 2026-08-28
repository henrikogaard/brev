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

import BrevDesign
import BrevThemes
import SwiftUI

enum CalendarContactsScopeDirection: Sendable, Hashable {
    case readOnlyBrowsingAfterDAVIntegration
}

enum CalendarContactsCapabilityStatus: Sendable, Hashable {
    case available
    case plannedAfterLiveDAV
    case outOfScope
}

enum CalendarContactsCapabilityKind: Sendable, Hashable {
    case calendarInvites
    case caldavInviteWrite
    case carddavComposeAutocomplete
    case readOnlyCalendarBrowsing
    case readOnlyContactsBrowsing
    case unifiedPIMSearch
    case fullCalendarEditing
    case fullContactManagement
}

struct CalendarContactsCapabilityPresentation: Sendable, Hashable, Identifiable {
    let kind: CalendarContactsCapabilityKind
    let title: String
    let detail: String
    let status: CalendarContactsCapabilityStatus
    let symbolName: String

    var id: CalendarContactsCapabilityKind { kind }
}

struct CalendarContactsScopeSummary: Sendable, Hashable {
    let direction: CalendarContactsScopeDirection
    let currentCapabilities: [CalendarContactsCapabilityPresentation]
    let plannedCapabilities: [CalendarContactsCapabilityPresentation]
    let outOfScopeCapabilities: [CalendarContactsCapabilityPresentation]
}

enum CalendarContactsScopePresentation {
    static let summary = CalendarContactsScopeSummary(
        direction: .readOnlyBrowsingAfterDAVIntegration,
        currentCapabilities: [
            CalendarContactsCapabilityPresentation(
                kind: .calendarInvites,
                title: String(localized: "Calendar invites", bundle: .module),
                detail: String(
                    localized: "Brev renders incoming invites in mail and lets supported accounts reply from the message.",
                    bundle: .module
                ),
                status: .available,
                symbolName: "envelope.badge"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .caldavInviteWrite,
                title: String(localized: "Accepted invite write target", bundle: .module),
                detail: String(
                    localized: "CalDAV remains a narrow destination for accepted invites, not a browsable calendar surface yet.",
                    bundle: .module
                ),
                status: .available,
                symbolName: "calendar.badge.plus"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .carddavComposeAutocomplete,
                title: String(localized: "Compose contact suggestions", bundle: .module),
                detail: String(
                    localized: "CardDAV contact data is used for recipient autocomplete and stays scoped to mail workflows.",
                    bundle: .module
                ),
                status: .available,
                symbolName: "person.crop.circle.badge.plus"
            )
        ],
        plannedCapabilities: [
            CalendarContactsCapabilityPresentation(
                kind: .readOnlyCalendarBrowsing,
                title: String(localized: "Read-only calendar browsing", bundle: .module),
                detail: String(
                    localized: "After #121 proves live CalDAV/CardDAV integration, Brev can add day/week/month browsing without event editing.",
                    bundle: .module
                ),
                status: .plannedAfterLiveDAV,
                symbolName: "calendar"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .readOnlyContactsBrowsing,
                title: String(localized: "Read-only contacts browsing", bundle: .module),
                detail: String(
                    localized: "After #121, CardDAV-backed people browsing can expose names, email addresses, organizations, and groups.",
                    bundle: .module
                ),
                status: .plannedAfterLiveDAV,
                symbolName: "person.2"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .unifiedPIMSearch,
                title: String(localized: "Calendar/contact search results", bundle: .module),
                detail: String(
                    localized: "After #121, mail search can grow scoped calendar/contact result groups without mixing provider semantics.",
                    bundle: .module
                ),
                status: .plannedAfterLiveDAV,
                symbolName: "magnifyingglass"
            )
        ],
        outOfScopeCapabilities: [
            CalendarContactsCapabilityPresentation(
                kind: .fullCalendarEditing,
                title: String(localized: "Full calendar editing", bundle: .module),
                detail: String(
                    localized: "Brev stays mail-first; creating arbitrary events, free/busy scheduling, and sending meeting invites remain outside this scope.",
                    bundle: .module
                ),
                status: .outOfScope,
                symbolName: "calendar.badge.exclamationmark"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .fullContactManagement,
                title: String(localized: "Full contacts management", bundle: .module),
                detail: String(
                    localized: "Brev stays mail-first; creating, editing, merging, and administering contacts are left to dedicated Contacts apps.",
                    bundle: .module
                ),
                status: .outOfScope,
                symbolName: "person.crop.circle.badge.xmark"
            )
        ]
    )
}

struct CalendarContactsSection: View {
    @Environment(\.brevTheme) private var theme

    private let summary = CalendarContactsScopePresentation.summary

    var body: some View {
        SectionScaffold(
            title: String(localized: "Calendar & Contacts", bundle: .module),
            subtitle: String(
                localized: "Brev stays mail-first while making calendar and contact data easier to inspect.",
                bundle: .module
            )
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                SettingsInfoCallout(
                    symbolName: "scope",
                    message: String(
                        localized: "Direction: add read-only calendar and contacts browsing after live CalDAV/CardDAV integration is proven; keep full PIM editing outside Brev.",
                        bundle: .module
                    ),
                    tone: .info
                )

                capabilityGroup(
                    title: String(localized: "Available now", bundle: .module),
                    subtitle: String(localized: "Calendar and contacts already support mail workflows.", bundle: .module),
                    symbolName: "checkmark.circle",
                    capabilities: summary.currentCapabilities
                )

                capabilityGroup(
                    title: String(localized: "Planned after DAV verification", bundle: .module),
                    subtitle: String(
                        localized: "Browsable surfaces wait for live CalDAV/CardDAV reliability work.",
                        bundle: .module
                    ),
                    symbolName: "clock.badge.checkmark",
                    capabilities: summary.plannedCapabilities
                )

                capabilityGroup(
                    title: String(localized: "Out of scope", bundle: .module),
                    subtitle: String(
                        localized: "Dedicated PIM authoring stays with system calendar and contacts apps.",
                        bundle: .module
                    ),
                    symbolName: "xmark.circle",
                    capabilities: summary.outOfScopeCapabilities
                )
            }
        }
    }

    private func capabilityGroup(
        title: String,
        subtitle: String,
        symbolName: String,
        capabilities: [CalendarContactsCapabilityPresentation]
    ) -> some View {
        SettingsGroup(title: title, subtitle: subtitle, symbolName: symbolName) {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                ForEach(capabilities) { capability in
                    capabilityRow(capability)
                    if capability.id != capabilities.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func capabilityRow(_ capability: CalendarContactsCapabilityPresentation) -> some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: capability.symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor(for: capability.status))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(capability.title)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(capability.detail)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusColor(for status: CalendarContactsCapabilityStatus) -> Color {
        switch status {
        case .available:
            return theme.success.color
        case .plannedAfterLiveDAV:
            return theme.info.color
        case .outOfScope:
            return theme.textTertiary.color
        }
    }
}
