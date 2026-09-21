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

/// The event editor sheet: create and edit for timed and all-day
/// events across Google Calendar and writable CalDAV (ADR-0072 #7).
///
/// The view owns a CalendarEventDraft it edits in place; saving goes
/// through CalendarEditingModel so capability checks, provider
/// dispatch, and conflict mapping stay out of the view. Repeating
/// events ask for a scope (all events / this and future) before the
/// mutation commits. Attendee edits disclose that the provider
/// notifies them.
public struct CalendarEventEditorView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar

    /// The editing model that owns writable targets and mutations.
    let editing: CalendarEditingModel
    /// Called after a successful save or delete so the browser reloads.
    let onSaved: () async -> Void

    @State private var draft: CalendarEventDraft
    /// The cached event being edited, when editing — drives the
    /// recurring-scope prompt and stays fixed for the sheet's life.
    private let editedEvent: PIMEvent?
    @State private var pendingScopeSave = false
    @State private var newAttendee = ""
    /// Reminder offsets the picker offers, in minutes.
    private static let reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440]

    /// Opens the editor for a new event.
    public init(
        editing: CalendarEditingModel,
        start: Date,
        onSaved: @escaping () async -> Void = {}
    ) {
        self.editing = editing
        self.onSaved = onSaved
        _draft = State(initialValue: CalendarEventDraft(start: start))
        editedEvent = nil
    }

    /// Opens the editor for an existing cached event.
    public init(
        editing: CalendarEditingModel,
        event: PIMEvent,
        onSaved: @escaping () async -> Void = {}
    ) {
        self.editing = editing
        self.onSaved = onSaved
        _draft = State(initialValue: CalendarEventDraft(event: event))
        editedEvent = event
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                    basicsSection
                    schedulingSection
                    if !draft.isAllDay {
                        timeZoneField
                    }
                    repeatSection
                    targetSection
                    locationField
                    attendeesSection
                    remindersSection
                    notesSection
                    if let lastError = editing.lastError {
                        Text(lastError)
                            .brevFont(.caption)
                            .foregroundStyle(theme.danger.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(BrevSpacing.lg)
            }
            .background(theme.bgPrimary.color)
            .navigationTitle(
                draft.isEditing
                    ? String(localized: "Edit Event", bundle: .module)
                    : String(localized: "New Event", bundle: .module)
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .confirmationDialog(
                recurringPromptTitle,
                isPresented: $pendingScopeSave,
                titleVisibility: .visible
            ) {
                ForEach(
                    CalendarRecurringEditScope.allCases,
                    id: \.self
                ) { scope in
                    Button(scope.title) {
                        Task { await commitSave(scope: scope) }
                    }
                }
                Button(
                    String(localized: "Cancel", bundle: .module),
                    role: .cancel
                ) {}
            } message: {
                Text(String(
                    localized:
                    "This is a repeating event. Your change can apply to the whole series or start a new series from this date.",
                    bundle: .module
                ))
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .onAppear {
            // A create draft picks the default target; an edit whose
            // collection lost write access falls back to it too.
            if draft.targetCollectionID == nil
                || editing.target(for: draft.targetCollectionID) == nil {
                draft.targetCollectionID = editing.defaultTarget?
                    .collection.id
            }
        }
    }

    private var recurringPromptTitle: String {
        String(localized: "Save changes to this event?", bundle: .module)
    }

    // MARK: - Sections

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            TextField(
                String(localized: "Title", bundle: .module),
                text: $draft.summary
            )
            .textFieldStyle(.plain)
            .brevFont(.title)
            .foregroundStyle(theme.textPrimary.color)
            Toggle(
                String(localized: "All day", bundle: .module),
                isOn: $draft.isAllDay
            )
            .toggleStyle(.switch)
        }
    }

    private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            DatePicker(
                String(localized: "Starts", bundle: .module),
                selection: $draft.start,
                displayedComponents: draft.isAllDay
                    ? [.date]
                    : [.date, .hourAndMinute]
            )
            DatePicker(
                String(localized: "Ends", bundle: .module),
                selection: $draft.end,
                in: draft.start...,
                displayedComponents: draft.isAllDay
                    ? [.date]
                    : [.date, .hourAndMinute]
            )
        }
    }

    private var timeZoneField: some View {
        LabeledContent(
            String(localized: "Time zone", bundle: .module)
        ) {
            TextField(
                String(
                    localized: "Local (floating)",
                    bundle: .module
                ),
                text: $draft.timeZoneIdentifier
            )
            .multilineTextAlignment(.trailing)
            #if os(iOS)
                .autocapitalization(.none)
            #endif
                .disableAutocorrection(true)
        }
    }

    @ViewBuilder
    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Picker(
                String(localized: "Repeat", bundle: .module),
                selection: $draft.repeatFrequency
            ) {
                ForEach(
                    CalendarEventDraft.RepeatFrequency.allCases,
                    id: \.self
                ) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            if draft.repeats {
                Stepper(
                    String(
                        localized:
                        "Every \(draft.repeatInterval)",
                        bundle: .module
                    ),
                    value: $draft.repeatInterval,
                    in: 1 ... 99
                )
                if draft.repeatFrequency == .weekly {
                    weekdayPicker
                }
                Picker(
                    String(localized: "Ends", bundle: .module),
                    selection: $draft.repeatEnd
                ) {
                    ForEach(
                        CalendarEventDraft.RepeatEnd.allCases,
                        id: \.self
                    ) { end in
                        Text(end.title).tag(end)
                    }
                }
                switch draft.repeatEnd {
                case .never:
                    EmptyView()
                case .onDate:
                    DatePicker(
                        String(localized: "End date", bundle: .module),
                        selection: $draft.repeatUntil,
                        in: draft.start...,
                        displayedComponents: [.date]
                    )
                case .afterCount:
                    Stepper(
                        String(
                            localized:
                            "\(draft.repeatCount) times",
                            bundle: .module
                        ),
                        value: $draft.repeatCount,
                        in: 1 ... 999
                    )
                }
            }
        }
    }

    /// Weekday toggles for weekly repeats — the start day is always
    /// implied, so the picker adds extra days.
    private var weekdayPicker: some View {
        HStack(spacing: BrevSpacing.xxs) {
            ForEach(ICSParser.Weekday.allCases, id: \.self) { day in
                let selected = draft.repeatWeekdays.contains(day)
                Button {
                    if selected {
                        draft.repeatWeekdays.remove(day)
                    } else {
                        draft.repeatWeekdays.insert(day)
                    }
                } label: {
                    Text(day.rawValue)
                        .brevFont(.caption)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(
                                selected
                                    ? theme.accent.color
                                    : theme.bgSecondary.color
                            )
                        )
                        .foregroundStyle(
                            selected
                                ? theme.bgPrimary.color
                                : theme.textPrimary.color
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekdayName(day))
                .accessibilityAddTraits(
                    selected ? .isSelected : []
                )
            }
        }
    }

    private func weekdayName(_ day: ICSParser.Weekday) -> String {
        switch day {
        case .monday:
            String(localized: "Monday", bundle: .module)
        case .tuesday:
            String(localized: "Tuesday", bundle: .module)
        case .wednesday:
            String(localized: "Wednesday", bundle: .module)
        case .thursday:
            String(localized: "Thursday", bundle: .module)
        case .friday:
            String(localized: "Friday", bundle: .module)
        case .saturday:
            String(localized: "Saturday", bundle: .module)
        case .sunday:
            String(localized: "Sunday", bundle: .module)
        }
    }

    private var targetSection: some View {
        Picker(
            String(localized: "Calendar", bundle: .module),
            selection: $draft.targetCollectionID
        ) {
            ForEach(editing.targets) { target in
                Text(target.title)
                    .tag(Optional(target.collection.id))
            }
        }
        .disabled(draft.isEditing && editing.targets.count < 2)
    }

    private var locationField: some View {
        LabeledContent(
            String(localized: "Location", bundle: .module)
        ) {
            TextField(
                String(localized: "Add a place", bundle: .module),
                text: $draft.location
            )
            .multilineTextAlignment(.trailing)
        }
    }

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(
                String(localized: "Attendees", bundle: .module),
                systemImage: "person.2"
            )
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
            ForEach(
                Array(draft.attendeeEmails.enumerated()),
                id: \.offset
            ) { index, email in
                HStack(spacing: BrevSpacing.sm) {
                    Text(email)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer()
                    Button {
                        draft.attendeeEmails.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(theme.danger.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(
                            localized: "Remove \(email)",
                            bundle: .module
                        )
                    )
                }
            }
            HStack(spacing: BrevSpacing.sm) {
                TextField(
                    String(
                        localized: "name@example.com",
                        bundle: .module
                    ),
                    text: $newAttendee
                )
                #if os(iOS)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                #endif
                .disableAutocorrection(true)
                .onSubmit(addAttendee)
                Button {
                    addAttendee()
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
                .disabled(
                    newAttendee.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
                .accessibilityLabel(
                    String(localized: "Add attendee", bundle: .module)
                )
            }
            if !draft.attendeeEmails.isEmpty {
                Text(String(
                    localized:
                    "The provider may notify attendees when you save.",
                    bundle: .module
                ))
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
            }
        }
    }

    private func addAttendee() {
        let email = newAttendee.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !email.isEmpty else { return }
        draft.attendeeEmails.append(email)
        newAttendee = ""
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(
                String(localized: "Reminders", bundle: .module),
                systemImage: "bell"
            )
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
            ForEach(
                Array(draft.reminderMinutes.enumerated()),
                id: \.offset
            ) { index, minutes in
                HStack(spacing: BrevSpacing.sm) {
                    Text(reminderLabel(minutes))
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer()
                    Button {
                        draft.reminderMinutes.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(theme.danger.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(
                            localized: "Remove reminder",
                            bundle: .module
                        )
                    )
                }
            }
            Menu {
                ForEach(Self.reminderOptions, id: \.self) { minutes in
                    Button(reminderLabel(minutes)) {
                        if !draft.reminderMinutes.contains(minutes) {
                            draft.reminderMinutes.append(minutes)
                            draft.reminderMinutes.sort()
                        }
                    }
                }
            } label: {
                Label(
                    String(localized: "Add reminder", bundle: .module),
                    systemImage: "plus.circle"
                )
                .brevFont(.body)
                .foregroundStyle(theme.accent.color)
            }
            #if os(macOS)
            .menuIndicator(.hidden)
            #endif
        }
    }

    private func reminderLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0:
            String(localized: "At start", bundle: .module)
        case 1440:
            String(localized: "1 day before", bundle: .module)
        case let m where m >= 60:
            String(
                localized: "\(m / 60) hours before",
                bundle: .module
            )
        default:
            String(
                localized: "\(minutes) minutes before",
                bundle: .module
            )
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(
                String(localized: "Notes", bundle: .module),
                systemImage: "text.alignleft"
            )
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
            TextEditor(text: $draft.notes)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .background(theme.bgSecondary.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: BrevRadius.sm)
                )
        }
    }

    // MARK: - Toolbar + actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel", bundle: .module)) {
                dismiss()
            }
            .disabled(editing.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(
                draft.isEditing
                    ? String(localized: "Save", bundle: .module)
                    : String(localized: "Add", bundle: .module)
            ) {
                requestSave()
            }
            .disabled(!draft.isValid || editing.isSaving)
        }
    }

    /// Save entry point: recurring edits ask for the scope first.
    private func requestSave() {
        if let event = editedEvent,
           editing.needsScopeChoice(for: event) {
            pendingScopeSave = true
        } else {
            Task { await commitSave(scope: nil) }
        }
    }

    private func commitSave(
        scope: CalendarRecurringEditScope?
    ) async {
        do {
            _ = try await editing.save(draft, scope: scope)
            await onSaved()
            dismiss()
        } catch {
            // The model already surfaced the error text inline.
        }
    }
}
