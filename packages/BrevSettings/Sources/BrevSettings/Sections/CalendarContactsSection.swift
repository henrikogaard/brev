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
import BrevDesign
import BrevThemes
import SwiftUI

enum CalendarContactsScopeDirection: Sendable, Hashable {
    /// ADR-0072: calendar and contacts arrive through optional Google and
    /// DAV sources; available actions depend on the connected source.
    case optionalConnectedSources
}

enum CalendarContactsCapabilityStatus: Sendable, Hashable {
    case available
    case notAvailableYet
    case outOfScope
}

enum CalendarContactsCapabilityKind: Sendable, Hashable {
    case calendarInvites
    case caldavInviteWrite
    case carddavComposeAutocomplete
    case davSourceConnect
    case googleSourceEnablement
    case readOnlyCalendarBrowsing
    case readOnlyContactsBrowsing
    case unifiedPIMSearch
    case eventAuthoring
    case contactAuthoring
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
    let unavailableCapabilities: [CalendarContactsCapabilityPresentation]
}

enum CalendarContactsScopePresentation {
    static let summary = CalendarContactsScopeSummary(
        direction: .optionalConnectedSources,
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
            ),
            CalendarContactsCapabilityPresentation(
                kind: .davSourceConnect,
                title: String(localized: "DAV source connections", bundle: .module),
                detail: String(
                    localized: "Connect CalDAV and CardDAV sources with standards discovery or a manual endpoint; credentials stay in Keychain.",
                    bundle: .module
                ),
                status: .available,
                symbolName: "person.crop.rectangle.stack"
            ),

            CalendarContactsCapabilityPresentation(
                kind: .googleSourceEnablement,
                title: String(localized: "Google Calendar and Contacts", bundle: .module),
                detail: String(
                    localized: "Enable Calendar or Contacts on a connected Google account from the Sources list; authorization adds the read-only scope for that feature.",
                    bundle: .module
                ),
                status: .available,
                symbolName: "g.circle"
            )
        ],
        unavailableCapabilities: [
            CalendarContactsCapabilityPresentation(
                kind: .readOnlyCalendarBrowsing,
                title: String(localized: "Calendar browsing", bundle: .module),
                detail: String(
                    localized: "Day, week, and month views over connected calendar sources.",
                    bundle: .module
                ),
                status: .notAvailableYet,
                symbolName: "calendar"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .readOnlyContactsBrowsing,
                title: String(localized: "Contacts browsing", bundle: .module),
                detail: String(
                    localized: "People browsing over connected contact sources with names, email addresses, organizations, and groups.",
                    bundle: .module
                ),
                status: .notAvailableYet,
                symbolName: "person.2"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .unifiedPIMSearch,
                title: String(localized: "Calendar/contact search results", bundle: .module),
                detail: String(
                    localized: "Scoped calendar and contact result groups inside mail search without mixing provider semantics.",
                    bundle: .module
                ),
                status: .notAvailableYet,
                symbolName: "magnifyingglass"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .eventAuthoring,
                title: String(localized: "Event editing", bundle: .module),
                detail: String(
                    localized: "Create and manage events on writable calendar sources.",
                    bundle: .module
                ),
                status: .notAvailableYet,
                symbolName: "calendar.badge.plus"
            ),
            CalendarContactsCapabilityPresentation(
                kind: .contactAuthoring,
                title: String(localized: "Contact editing", bundle: .module),
                detail: String(
                    localized: "Create and manage contacts on writable contact sources.",
                    bundle: .module
                ),
                status: .notAvailableYet,
                symbolName: "person.crop.circle.badge.plus"
            )
        ]
    )
}

struct CalendarContactsSection: View {
    @Environment(\.brevTheme) private var theme

    /// Live source-list model; nil in previews and tests that only render
    /// the capability summary.
    let model: PIMSourceSettingsModel?
    /// Google mail accounts eligible for PIM feature enablement.
    let googleAccounts: [BrevAccount]

    private let summary = CalendarContactsScopePresentation.summary

    init(
        model: PIMSourceSettingsModel? = nil,
        googleAccounts: [BrevAccount] = []
    ) {
        self.model = model
        self.googleAccounts = googleAccounts
    }

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
                        localized: "Calendar and Contacts are being added through optional Google and DAV sources. Available actions depend on the connected source.",
                        bundle: .module
                    ),
                    tone: .info
                )

                if let model {
                    PIMSourcesSettingsView(
                        model: model,
                        googleAccounts: googleAccounts
                    )
                }

                capabilityGroup(
                    title: String(localized: "Available now", bundle: .module),
                    subtitle: String(localized: "Calendar and contacts already support mail workflows.", bundle: .module),
                    symbolName: "checkmark.circle",
                    capabilities: summary.currentCapabilities
                )

                capabilityGroup(
                    title: String(localized: "Not available yet", bundle: .module),
                    subtitle: String(
                        localized: "Accepted on the product roadmap; each arrives as its source work ships.",
                        bundle: .module
                    ),
                    symbolName: "clock",
                    capabilities: summary.unavailableCapabilities
                )
            }
        }
        .task {
            await model?.load()
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
                HStack(spacing: BrevSpacing.xs) {
                    Text(capability.title)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                    if capability.status == .notAvailableYet {
                        notAvailableBadge
                    }
                }
                Text(capability.detail)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notAvailableBadge: some View {
        Text(String(localized: "Not available yet", bundle: .module))
            .brevFont(.caption)
            .foregroundStyle(theme.textTertiary.color)
            .padding(.horizontal, BrevSpacing.xxs)
            .padding(.vertical, 1)
            .brevQuietSurface(cornerRadius: BrevRadius.sm)
    }

    private func statusColor(for status: CalendarContactsCapabilityStatus) -> Color {
        switch status {
        case .available:
            return theme.success.color
        case .notAvailableYet, .outOfScope:
            return theme.textTertiary.color
        }
    }
}
