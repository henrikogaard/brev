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

/// Sheet that lets the composer pick a future send time.
///
/// The sheet emits the chosen `Date` (or `nil` for "Send now") via
/// `onConfirm`. The host view is responsible for setting the
/// composer state and dismissing the sheet; the sheet itself is
/// purely a picker.
struct ScheduleSendSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOption: ScheduleSendDateResolver.Option
    @State private var customDate: Date

    let initiallyScheduledDate: Date?
    let now: () -> Date
    /// Calendar and locale used to resolve and label the quick picks;
    /// injectable so snapshots do not depend on the machine's zone or 24-hour
    /// setting.
    let calendar: Calendar
    let locale: Locale
    let onConfirm: (Date?) -> Void

    init(
        initiallyScheduledDate: Date?,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        locale: Locale = .current,
        onConfirm: @escaping (Date?) -> Void
    ) {
        self.initiallyScheduledDate = initiallyScheduledDate
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.onConfirm = onConfirm
        let resolved = ScheduleSendSheet.resolveInitialOption(
            scheduled: initiallyScheduledDate,
            now: now(),
            calendar: calendar
        )
        _selectedOption = State(initialValue: resolved.option)
        _customDate = State(initialValue: resolved.customDate)
    }

    var body: some View {
        #if os(iOS)
        nativeBody
        #else
        desktopBody
        #endif
    }

    #if os(iOS)
    /// iOS: a standard form sheet. Cancel and Schedule live in the navigation
    /// bar, the content scrolls, and the custom date picker only appears when
    /// "Pick Date & Time" is chosen.
    private var nativeBody: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ScheduleSendDateResolver.Option.allCases) { option in
                        nativeOptionRow(option)
                    }
                }
                .listRowBackground(theme.bgSecondary.color)

                if selectedOption == .custom {
                    Section {
                        customDatePicker
                    }
                    .listRowBackground(theme.bgSecondary.color)
                }

                Section {
                    Label {
                        Text(ScheduleSendReliabilityPresentation.localDeliveryNotice)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textSecondary.color)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(theme.accent.color)
                    }
                }
                .listRowBackground(theme.bgSecondary.color)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bgPrimary.color)
            .navigationTitle(Text("Schedule send", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onConfirm(chosenDate)
                        dismiss()
                    } label: {
                        Text(confirmTitle, bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func nativeOptionRow(_ option: ScheduleSendDateResolver.Option) -> some View {
        Button {
            selectOption(option)
        } label: {
            HStack(spacing: BrevSpacing.sm) {
                Image(systemName: option.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.title)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    if let resolved = optionSubtitle(option) {
                        Text(resolved)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textSecondary.color)
                    }
                }
                Spacer(minLength: BrevSpacing.sm)
                if selectedOption == option {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.accent.color)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selectedOption == option ? .isSelected : [])
    }
    #endif

    private var desktopBody: some View {
        VStack(spacing: 0) {
            header
            optionsList
            if selectedOption == .custom {
                BrevDivider()
                customDatePicker
            }
            deliveryNotice
            BrevDivider()
            actions
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 400)
        #endif
        .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
        .brevWindowTranslucency(windowRole: .utility)
    }

    private var header: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "calendar.badge.clock")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .accessibilityHidden(true)
            Text("Schedule send", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer(minLength: BrevSpacing.sm)
            BrevIconButton(
                systemName: "xmark",
                accessibilityLabel: "Close schedule sheet",
                bundle: .module
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.md)
    }

    private var optionsList: some View {
        VStack(spacing: 0) {
            ForEach(ScheduleSendDateResolver.Option.allCases) { option in
                optionRow(option)
                if option != ScheduleSendDateResolver.Option.allCases.last {
                    BrevDivider()
                        .padding(.leading, BrevSpacing.xl)
                }
            }
        }
    }

    private func optionRow(_ option: ScheduleSendDateResolver.Option) -> some View {
        Button {
            selectOption(option)
        } label: {
            HStack(spacing: BrevSpacing.sm) {
                Image(systemName: option.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(option.title)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer(minLength: BrevSpacing.sm)
                if let resolved = optionSubtitle(option) {
                    Text(resolved)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textTertiary.color)
                }
                Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(
                        selectedOption == option
                            ? theme.accent.color
                            : theme.textTertiary.color
                    )
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrevSpacing.lg)
            .padding(.vertical, BrevSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selectedOption == option ? .isSelected : [])
    }

    private func selectOption(_ option: ScheduleSendDateResolver.Option) {
        selectedOption = option
        if option == .custom, customDate < now() {
            customDate = ScheduleSendDateResolver.date(
                for: .tomorrowNine,
                now: now()
            ) ?? now().addingTimeInterval(60 * 60)
        }
    }

    private func optionSubtitle(_ option: ScheduleSendDateResolver.Option) -> String? {
        guard option != .sendNow, option != .custom,
              let date = ScheduleSendDateResolver.date(for: option, now: now(), calendar: calendar)
        else {
            return nil
        }
        #if os(iOS)
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = locale
        style.timeZone = calendar.timeZone
        return date.formatted(style)
        #else
        return ScheduleSendDateResolver.formattedScheduleDate(date, calendar: calendar)
        #endif
    }

    private var customDatePicker: some View {
        DatePicker(
            String(localized: "Send at", bundle: .module),
            selection: $customDate,
            in: now()...,
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.graphical)
        .environment(\.calendar, calendar)
        .environment(\.locale, locale)
        .labelsHidden()
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.md)
        .tint(theme.accent.color)
    }

    private var deliveryNotice: some View {
        BrevInlineStatus(
            message: ScheduleSendReliabilityPresentation.localDeliveryNotice,
            tone: .info,
            lineLimit: 3
        )
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.bottom, BrevSpacing.md)
    }

    private var actions: some View {
        HStack(spacing: BrevSpacing.sm) {
            BrevButton("Cancel", style: .secondary, bundle: .module) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer(minLength: BrevSpacing.sm)

            BrevButton(confirmTitle, style: .primary, bundle: .module) {
                onConfirm(chosenDate)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.md)
    }

    private var confirmTitle: LocalizedStringKey {
        selectedOption == .sendNow ? "Send now" : "Schedule"
    }

    private var chosenDate: Date? {
        switch selectedOption {
        case .sendNow: nil
        case .custom: max(customDate, now())
        case let option:
            ScheduleSendDateResolver.date(for: option, now: now(), calendar: calendar)
        }
    }

    private struct ResolvedInitialOption {
        let option: ScheduleSendDateResolver.Option
        let customDate: Date
    }

    /// Snap an existing `scheduledFor` value to the most likely
    /// quick-pick, falling back to `.custom` when nothing matches.
    private static func resolveInitialOption(
        scheduled: Date?,
        now: Date,
        calendar: Calendar
    ) -> ResolvedInitialOption {
        let oneHour = now.addingTimeInterval(60 * 60)
        let initialCustom = max(scheduled ?? oneHour, now)

        guard let scheduled else {
            return ResolvedInitialOption(option: .tomorrowNine, customDate: initialCustom)
        }

        for option in ScheduleSendDateResolver.Option.allCases where option != .custom {
            guard let resolved = ScheduleSendDateResolver.date(for: option, now: now, calendar: calendar) else {
                continue
            }
            if calendar.isDate(resolved, equalTo: scheduled, toGranularity: .minute) {
                return ResolvedInitialOption(option: option, customDate: initialCustom)
            }
        }
        return ResolvedInitialOption(option: .custom, customDate: initialCustom)
    }
}
