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
import BrevDesign
import BrevThemes
import SwiftUI

/// Read-only detail pane for one cached calendar event (ADR-0072).
///
/// Shows every field the shared model carries: title, status, time range
/// with the provider's time zone, recurrence, location, conference join
/// link, organizer, attendees with RSVP state, reminders, and the
/// provider's description. Source and collection provenance close the
/// pane so ownership stays visible. When the parent supplies edit or
/// delete actions (writable source, issue #7) an action row appears
/// under the header; repeating deletes ask for the scope here so the
/// editor sheet stays create/save only.
public struct CalendarEventDetailView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.openURL) private var openURL

    let event: PIMEvent
    let collection: PIMCollection?
    let source: PIMSource?
    /// Opens the editor for this event; nil hides the Edit action.
    let onEdit: (() -> Void)?
    /// Deletes the event under the chosen recurring scope; nil hides
    /// the Delete action. nil scope means a non-recurring delete.
    let onDelete: ((CalendarRecurringEditScope?) -> Void)?
    /// Whether the event belongs to a repeating series — the delete
    /// confirmation asks for a scope only then.
    let isRecurring: Bool

    @State private var showsDeleteConfirmation = false

    public init(
        event: PIMEvent,
        collection: PIMCollection? = nil,
        source: PIMSource? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: ((CalendarRecurringEditScope?) -> Void)? = nil,
        isRecurring: Bool = false
    ) {
        self.event = event
        self.collection = collection
        self.source = source
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.isRecurring = isRecurring
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                header
                if onEdit != nil || onDelete != nil || deepLinkURL != nil {
                    actionRow
                }
                if let conference = event.conference {
                    conferenceSection(conference)
                } else if let conferenceURL = event.conferenceURL,
                          let url = URL(string: conferenceURL) {
                    joinButton(url)
                }
                if !event.attendees.isEmpty || event.organizer != nil {
                    peopleSection
                }
                if !event.reminders.isEmpty {
                    remindersSection
                }
                if !event.attachments.isEmpty {
                    attachmentsSection
                }
                if let description = event.eventDescription,
                   !description.isEmpty {
                    descriptionSection(description)
                }
                provenanceFooter
            }
            .padding(BrevSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bgPrimary.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(localized: "Event details", bundle: .module)
        )
        .confirmationDialog(
            String(localized: "Delete this event?", bundle: .module),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if isRecurring {
                ForEach(
                    CalendarRecurringEditScope.allCases,
                    id: \.self
                ) { scope in
                    Button(scope.title, role: .destructive) {
                        onDelete?(scope)
                    }
                }
            } else {
                Button(
                    String(localized: "Delete Event", bundle: .module),
                    role: .destructive
                ) {
                    onDelete?(nil)
                }
            }
            Button(
                String(localized: "Cancel", bundle: .module),
                role: .cancel
            ) {}
        } message: {
            if isRecurring {
                Text(String(
                    localized:
                    "This is a repeating event. You can delete the whole series or end it before this date.",
                    bundle: .module
                ))
            }
        }
    }

    // MARK: - Actions

    /// Edit/Delete affordances for writable sources. Both stay plain
    /// buttons so the row reads as inline text actions, not chrome.
    private var actionRow: some View {
        HStack(spacing: BrevSpacing.lg) {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label(
                        String(localized: "Edit", bundle: .module),
                        systemImage: "pencil"
                    )
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
            }
            if onDelete != nil {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label(
                        String(localized: "Delete", bundle: .module),
                        systemImage: "trash"
                    )
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.danger.color)
                }
                .buttonStyle(.plain)
            }
            if let deepLinkURL {
                Button {
                    PIMDeepLinkCopy.copy(deepLinkURL)
                } label: {
                    Label(
                        String(localized: "Copy Link", bundle: .module),
                        systemImage: "link"
                    )
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    String(
                        localized: "Copies a link that reopens this event in Brev",
                        bundle: .module
                    )
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The brev:// link that reopens this cached event (#10).
    private var deepLinkURL: URL? {
        PIMDeepLinkPolicy.url(forEventID: event.id)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.sm) {
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .fill(collectionColor)
                    .frame(width: 4, height: 28)
                    .accessibilityHidden(true)
                Text(event.summary
                    ?? CalendarEventPresentation.untitledTitle())
                    .brevFont(.title)
                    .foregroundStyle(theme.textPrimary.color)
                    .strikethrough(event.status == .cancelled)
                if let statusText = CalendarEventPresentation.statusText(
                    for: event.status
                ) {
                    Text(statusText)
                        .brevFont(.caption)
                        .foregroundStyle(theme.warning.color)
                        .padding(.horizontal, BrevSpacing.xs)
                        .padding(.vertical, BrevSpacing.xxs)
                        .background(
                            Capsule().fill(theme.bgSecondary.color)
                        )
                }
            }

            detailRow(
                symbol: "clock",
                label: String(localized: "When", bundle: .module)
            ) {
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(CalendarEventPresentation.detailRangeText(
                        for: event
                    ))
                    if let timeZoneIdentifier = event.timeZoneIdentifier,
                       !event.isAllDay {
                        Text(timeZoneIdentifier)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                    }
                }
            }

            if let rule = event.recurrenceRule {
                detailRow(
                    symbol: "repeat",
                    label: String(localized: "Repeats", bundle: .module)
                ) {
                    Text(CalendarEventPresentation.recurrenceSummary(
                        for: rule,
                        calendar: calendar
                    ))
                }
            }

            if let location = event.location, !location.isEmpty {
                detailRow(
                    symbol: "mappin",
                    label: String(localized: "Location", bundle: .module)
                ) {
                    Text(location)
                }
            }
        }
    }

    // MARK: - Join link

    /// The conference block (#13): provider name and status, the join
    /// button when a link exists, and phone entry points as tappable
    /// tel: rows. Unknown providers render the same chrome — no
    /// provider-specific controls appear here.
    private func conferenceSection(_ conference: PIMConference) -> some View {
        detailSection(
            title: conference.name
                ?? String(localized: "Video call", bundle: .module),
            symbol: "video"
        ) {
            if conference.status == .pending {
                Text(
                    String(
                        localized:
                        "The video call is being created and appears after the next sync.",
                        bundle: .module
                    )
                )
                .brevFont(.caption)
                .foregroundStyle(theme.warning.color)
            } else if conference.status == .failure {
                Text(
                    String(
                        localized:
                        "The provider could not create the video call. The event itself is saved.",
                        bundle: .module
                    )
                )
                .brevFont(.caption)
                .foregroundStyle(theme.danger.color)
            }
            if let joinURL = conference.joinURL,
               let url = URL(string: joinURL) {
                joinButton(url)
            }
            ForEach(Array(conference.dialIns.enumerated()), id: \.offset) { _, dialIn in
                dialInRow(dialIn)
            }
        }
    }

    private func dialInRow(_ dialIn: PIMConference.DialIn) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "phone")
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityHidden(true)
            if let url = URL(string: dialIn.uri) {
                Button {
                    openURL(url)
                } label: {
                    Text(dialIn.label ?? dialIn.uri)
                        .brevFont(.body)
                        .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
            } else {
                Text(dialIn.label ?? dialIn.uri)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
            }
            if let pin = dialIn.pin, !pin.isEmpty {
                Text(
                    String(
                        localized: "PIN \(pin)",
                        bundle: .module
                    )
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func joinButton(_ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label(
                String(localized: "Join meeting", bundle: .module),
                systemImage: "video"
            )
            .brevFont(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrevSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .fill(theme.accent.color)
            )
            .foregroundStyle(theme.bgPrimary.color)
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            String(
                localized: "Opens the conference link",
                bundle: .module
            )
        )
    }

    // MARK: - People

    private var peopleSection: some View {
        detailSection(
            title: String(localized: "People", bundle: .module),
            symbol: "person.2"
        ) {
            if let organizer = event.organizer {
                personRow(
                    name: organizer.name,
                    email: organizer.email,
                    role: String(localized: "Organizer", bundle: .module),
                    rsvp: nil
                )
            }
            ForEach(event.attendees, id: \.email) { attendee in
                personRow(
                    name: attendee.name,
                    email: attendee.email,
                    role: nil,
                    rsvp: attendee.rsvp
                )
            }
        }
    }

    private func personRow(
        name: String?,
        email: String,
        role: String?,
        rsvp: PIMEventPerson.RSVP?
    ) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(name ?? email)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                if name != nil || role != nil {
                    Text(
                        [name != nil ? email : nil, role]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                    )
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                }
            }
            Spacer(minLength: BrevSpacing.sm)
            if let rsvp {
                Text(CalendarEventPresentation.rsvpText(for: rsvp))
                    .brevFont(.caption)
                    .foregroundStyle(rsvpColor(for: rsvp))
                    .padding(.horizontal, BrevSpacing.xs)
                    .padding(.vertical, BrevSpacing.xxs)
                    .background(
                        Capsule().fill(theme.bgSecondary.color)
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rsvpColor(for rsvp: PIMEventPerson.RSVP) -> Color {
        switch rsvp {
        case .accepted: return theme.success.color
        case .declined: return theme.danger.color
        case .tentative: return theme.warning.color
        case .needsAction, .delegated, .unknown:
            return theme.textSecondary.color
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        detailSection(
            title: String(localized: "Reminders", bundle: .module),
            symbol: "bell"
        ) {
            ForEach(Array(event.reminders.enumerated()), id: \.offset) { _, reminder in
                Text(CalendarEventPresentation.reminderText(
                    for: reminder
                ))
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
            }
        }
    }

    // MARK: - Description

    /// Drive link attachments (#14) — tappable rows that open the URL.
    private var attachmentsSection: some View {
        detailSection(
            title: String(localized: "Attachments", bundle: .module),
            symbol: "paperclip"
        ) {
            ForEach(
                Array(event.attachments.enumerated()),
                id: \.offset
            ) { _, attachment in
                if let url = URL(string: attachment.url) {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: BrevSpacing.sm) {
                            Image(systemName: "link")
                                .foregroundStyle(theme.accent.color)
                            Text(attachment.title ?? attachment.url)
                                .brevFont(.body)
                                .foregroundStyle(theme.textPrimary.color)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(theme.textTertiary.color)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func descriptionSection(_ description: String) -> some View {
        detailSection(
            title: String(localized: "Notes", bundle: .module),
            symbol: "text.alignleft"
        ) {
            Text(description)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Provenance

    private var provenanceFooter: some View {
        HStack(spacing: BrevSpacing.xs) {
            if let collection {
                Circle()
                    .fill(collectionColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(collection.displayName)
            }
            if let source {
                Text(verbatim: "·")
                Text(source.displayName)
            }
            if let providerUpdatedAt = event.providerUpdatedAt {
                Text(verbatim: "·")
                Text(String(
                    localized:
                    "Updated \(providerUpdatedAt.formatted(.dateTime.month().day().hour().minute()))",
                    bundle: .module
                ))
            }
        }
        .brevFont(.caption)
        .foregroundStyle(theme.textTertiary.color)
    }

    // MARK: - Building blocks

    private func detailRow<Content: View>(
        symbol: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: symbol)
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(label)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                content()
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detailSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(title, systemImage: symbol)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                content()
            }
            .padding(.leading, BrevSpacing.xs)
        }
    }

    private var collectionColor: Color {
        guard let hex = collection?.colorHex else {
            return theme.accent.color
        }
        return BrevColor(hex).color
    }
}
