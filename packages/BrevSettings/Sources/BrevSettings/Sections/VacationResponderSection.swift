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

// MARK: - VacationResponderSection

/// Vacation auto-reply, per account.
///
/// State comes from the `AutoReplyManaging` extension service when the
/// account supports it. A forwarding pane used to live here too, but it
/// only ever wrote to UserDefaults — no provider endpoint was ever wired,
/// so it told the user their mail was being forwarded when it was not.
public struct VacationResponderSection: View {
    @Environment(\.brevTheme) private var theme

    private let settingsStore: SettingsPersistenceStore
    private let accounts: [BrevAccount]
    private let currentAccountID: BrevAccount.ID?
    private let backendProvider: @MainActor (BrevAccount.ID) -> (any MailBackend)?

    public init(
        settingsStore: SettingsPersistenceStore,
        accounts: [BrevAccount],
        currentAccountID: BrevAccount.ID?,
        backendProvider: @escaping @MainActor (BrevAccount.ID) -> (any MailBackend)?
    ) {
        self.settingsStore = settingsStore
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.backendProvider = backendProvider
    }

    public var body: some View {
        SectionScaffold(
            title: String(localized: "Auto-Reply", bundle: .module),
            subtitle: String(localized: "Send an automatic reply while you are away.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                if accounts.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "person.crop.circle.badge.questionmark",
                        message: String(
                            localized: "Sign in to at least one account to manage automatic replies.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                } else {
                    ForEach(accounts) { account in
                        accountCard(for: account)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accountCard(for account: BrevAccount) -> some View {
        let backend = backendProvider(account.id)
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            accountHeader(account)
            vacationCard(account: account, backend: backend)
        }
        .padding(BrevSpacing.md)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private func accountHeader(_ account: BrevAccount) -> some View {
        HStack(alignment: .center, spacing: BrevSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(account.emailAddress)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            Spacer(minLength: BrevSpacing.md)
            if account.id == currentAccountID {
                Text("Default", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.accent.color)
            }
        }
    }

    @ViewBuilder
    private func vacationCard(account: BrevAccount, backend: (any MailBackend)?) -> some View {
        if let backend,
           let service = backend.extensionService(AutoReplyManaging.self) {
            VacationResponderPane(
                backend: backend,
                service: service
            )
        } else {
            unsupportedVacationCallout
        }
    }

    private var unsupportedVacationCallout: some View {
        SettingsInfoCallout(
            symbolName: "exclamationmark.triangle",
            message: String(localized: "Automatic replies are not supported by this account.", bundle: .module),
            tone: .warning
        )
    }
}

// MARK: - Vacation responder pane

private struct VacationResponderPane: View {
    @Environment(\.brevTheme) private var theme
    let backend: any MailBackend
    let service: any AutoReplyManaging

    @State private var settings: [VacationResponderSettings] = []
    @State private var draft: VacationResponderDraftState
    @State private var loadError: String?
    @State private var saveMessage: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isResettingCounter = false
    @State private var lastLoadedAccountID: String?

    init(backend: any MailBackend, service: any AutoReplyManaging) {
        self.backend = backend
        self.service = service
        _draft = State(initialValue: VacationResponderDraftState.empty)
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "Vacation responder", bundle: .module),
            subtitle: String(localized: "Provider-side automatic reply for this account.", bundle: .module),
            symbolName: "airplane.departure"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if isLoading && settings.isEmpty {
                    HStack(spacing: BrevSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading vacation responder…", bundle: .module)
                            .brevFont(.body)
                            .foregroundStyle(theme.textSecondary.color)
                    }
                } else {
                    toggleRow
                    scheduleRows
                    messageRow
                    excludedRecipientsRow
                }

                if let loadError {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: loadError,
                        tone: .warning
                    )
                }
                if let saveMessage {
                    SettingsInfoCallout(
                        symbolName: "checkmark.circle",
                        message: saveMessage,
                        tone: .success
                    )
                }

                HStack(spacing: BrevSpacing.sm) {
                    BrevButton(
                        isSaving ? String(localized: "Saving…", bundle: .module) : String(
                            localized: "Save vacation responder",
                            bundle: .module
                        ),
                        style: .primary
                    ) {
                        Task { await save() }
                    }
                    .disabled(isVacationBusy || !draft.canSave)

                    BrevButton(
                        isLoading ? String(localized: "Refreshing…", bundle: .module) : String(
                            localized: "Refresh",
                            bundle: .module
                        ),
                        style: .secondary
                    ) {
                        Task { await load(force: true) }
                    }
                    .disabled(isVacationBusy)

                    BrevButton(
                        isResettingCounter ? String(localized: "Resetting…", bundle: .module) : String(
                            localized: "Reset counter",
                            bundle: .module
                        ),
                        style: .tertiary
                    ) {
                        Task { await resetCounter() }
                    }
                    .disabled(isVacationBusy || draft.id == nil)

                    BrevButton(String(localized: "Disable", bundle: .module), style: .destructive) {
                        Task { await disable() }
                    }
                    .disabled(isVacationBusy || draft.id == nil)

                    Spacer(minLength: 0)
                }
            }
        }
        .task(id: backend.account.id) { await load() }
    }

    private var isVacationBusy: Bool {
        isLoading || isSaving || isResettingCounter
    }

    private var toggleRow: some View {
        SettingsToggleRow(
            symbolName: "moon",
            title: String(localized: "Send automatic reply", bundle: .module),
            subtitle: String(localized: "Reply to incoming messages while you're away.", bundle: .module),
            isOn: $draft.isEnabled
        )
    }

    private var scheduleRows: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            DatePicker(
                String(localized: "Active from", bundle: .module),
                selection: startsAtBinding,
                displayedComponents: [.date, .hourAndMinute]
            )
            DatePicker(
                String(localized: "Active until", bundle: .module),
                selection: endsAtBinding,
                displayedComponents: [.date, .hourAndMinute]
            )
            SettingsToggleRow(
                symbolName: "calendar.badge.clock",
                title: String(localized: "Repeats on weekdays", bundle: .module),
                subtitle: String(localized: "Send the auto-reply only on these weekdays.", bundle: .module),
                isOn: recurrenceEnabledBinding
            )
            if draft.recurrenceEnabled {
                Picker(String(localized: "Days", bundle: .module), selection: weekdayBinding) {
                    ForEach(MailWeekday.allCases, id: \.self) { day in
                        Text(weekdayLabel(day)).tag(day)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var messageRow: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("Reply message", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Plain text. Leave a blank line between paragraphs.", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            TextEditor(text: $draft.message)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(BrevSpacing.xs)
                .background(theme.bgSecondary.color.opacity(0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: BrevRadius.sm)
                        .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            if let validationError = draft.firstValidationError {
                Text(validationError)
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
            }
        }
    }

    private var excludedRecipientsRow: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("Skip these recipients (optional)", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Comma-separated. The auto-reply won't be sent to these addresses.", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            TextField("name@example.org, other@example.org", text: $draft.excludedRecipientsText)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Bindings

    private var startsAtBinding: Binding<Date> {
        Binding(
            get: { draft.startsAt ?? Date() },
            set: { draft.startsAt = $0 }
        )
    }

    private var endsAtBinding: Binding<Date> {
        Binding(
            get: { draft.endsAt ?? Date().addingTimeInterval(60 * 60 * 24 * 7) },
            set: { draft.endsAt = $0 }
        )
    }

    private var recurrenceEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.recurrenceEnabled },
            set: { draft.recurrenceEnabled = $0 }
        )
    }

    private var weekdayBinding: Binding<MailWeekday> {
        Binding(
            get: { draft.primaryWeekday ?? .monday },
            set: { draft.primaryWeekday = $0 }
        )
    }

    // MARK: - Load / save

    private func load(force: Bool = false) async {
        guard !isLoading, force || lastLoadedAccountID != backend.account.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let sourceID = currentSourceID
            let fetched = try await service.vacationResponderSettings(for: sourceID)
            settings = fetched
            let selected = fetched.first
            draft = selected.map(VacationResponderDraftState.init(settings:)) ?? .empty
            lastLoadedAccountID = backend.account.id
            loadError = nil
        } catch {
            loadError = String(localized: "Couldn't load vacation responder: \(error.localizedDescription)", bundle: .module)
        }
    }

    private func save() async {
        guard draft.canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let payload = draft.makeDraft()
            let saved = try await service.saveVacationResponder(payload, sourceID: currentSourceID)
            settings = settings
                .filter { $0.id != saved.id }
                + [saved]
            draft = VacationResponderDraftState(settings: saved)
            saveMessage = String(localized: "Vacation responder saved.", bundle: .module)
            loadError = nil
        } catch {
            loadError = String(localized: "Couldn't save vacation responder: \(error.localizedDescription)", bundle: .module)
        }
    }

    private func disable() async {
        guard let id = draft.id else { return }
        do {
            try await service.deleteVacationResponder(id: id, sourceID: currentSourceID)
            settings = settings.filter { $0.id != id }
            draft = .empty
            saveMessage = String(localized: "Vacation responder disabled.", bundle: .module)
        } catch {
            loadError = String(localized: "Couldn't disable vacation responder: \(error.localizedDescription)", bundle: .module)
        }
    }

    private func resetCounter() async {
        guard let id = draft.id else { return }
        isResettingCounter = true
        defer { isResettingCounter = false }
        do {
            try await service.resetVacationResponderCounter(id: id, sourceID: currentSourceID)
            saveMessage = String(localized: "Counter reset. New replies will be sent to incoming messages.", bundle: .module)
        } catch {
            loadError = String(localized: "Couldn't reset counter: \(error.localizedDescription)", bundle: .module)
        }
    }

    private var currentSourceID: MailSourceID {
        MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
    }

    private func weekdayLabel(_ day: MailWeekday) -> String {
        switch day {
        case .monday: return String(localized: "Mon", bundle: .module)
        case .tuesday: return String(localized: "Tue", bundle: .module)
        case .wednesday: return String(localized: "Wed", bundle: .module)
        case .thursday: return String(localized: "Thu", bundle: .module)
        case .friday: return String(localized: "Fri", bundle: .module)
        case .saturday: return String(localized: "Sat", bundle: .module)
        case .sunday: return String(localized: "Sun", bundle: .module)
        }
    }
}

// MARK: - Vacation responder draft state

private struct VacationResponderDraftState: Equatable {
    var id: String?
    var name: String
    var isEnabled: Bool
    var message: String
    var startsAt: Date?
    var endsAt: Date?
    var recurrenceEnabled: Bool
    var primaryWeekday: MailWeekday?
    var excludedRecipientsText: String

    static let empty = VacationResponderDraftState(
        id: nil,
        name: String(localized: "Vacation responder", bundle: .module),
        isEnabled: false,
        message: "",
        startsAt: nil,
        endsAt: nil,
        recurrenceEnabled: false,
        primaryWeekday: nil,
        excludedRecipientsText: ""
    )

    init(settings: VacationResponderSettings) {
        id = settings.id
        name = settings.name
        isEnabled = settings.isEnabled
        message = settings.message
        startsAt = settings.schedule.startsAt
        endsAt = settings.schedule.endsAt
        switch settings.schedule.recurrence {
        case .none:
            recurrenceEnabled = false
            primaryWeekday = nil
        case .weekly(let days):
            recurrenceEnabled = true
            primaryWeekday = days.sorted(by: Self.weekdayOrder).first
        }
        excludedRecipientsText = settings.excludedRecipients.joined(separator: ", ")
    }

    init(
        id: String?,
        name: String,
        isEnabled: Bool,
        message: String,
        startsAt: Date?,
        endsAt: Date?,
        recurrenceEnabled: Bool,
        primaryWeekday: MailWeekday?,
        excludedRecipientsText: String
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.message = message
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.recurrenceEnabled = recurrenceEnabled
        self.primaryWeekday = primaryWeekday
        self.excludedRecipientsText = excludedRecipientsText
    }

    var canSave: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var firstValidationError: String? {
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Add a message before saving.", bundle: .module)
        }
        if let starts = startsAt, let ends = endsAt, ends < starts {
            return String(localized: "End date must be after the start date.", bundle: .module)
        }
        return nil
    }

    func makeDraft() -> VacationResponderDraft {
        let trimmedExcluded = excludedRecipientsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let recurrence: VacationResponderRecurrence = {
            guard recurrenceEnabled, let day = primaryWeekday else {
                return .none
            }
            return .weekly(days: [day])
        }()
        return VacationResponderDraft(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "Vacation responder", bundle: .module)
                : name,
            isEnabled: isEnabled,
            message: message,
            startsAt: startsAt,
            endsAt: endsAt,
            recurrence: recurrence,
            excludedRecipients: trimmedExcluded,
            replyFrom: nil
        )
    }

    private static func weekdayOrder(_ a: MailWeekday, _ b: MailWeekday) -> Bool {
        let order: [MailWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        return order.firstIndex(of: a).map { aIndex in
            order.firstIndex(of: b).map { bIndex in
                aIndex < bIndex
            } ?? false
        } ?? false
    }
}
