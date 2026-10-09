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

/// Sheet for picking when to wake a snoozed message.
///
/// iOS presents a navigation-stack sheet with an inset-grouped list (quick
/// options with their resolved wake time, then a pushed date and time screen);
/// macOS keeps its compact custom layout.
struct SnoozePickerView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    let header: MessageHeader
    let sourceID: MailSourceID?
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void
    /// Reference "current" time; fixed at presentation so every row and the
    /// custom picker's lower bound agree. Tests and snapshots pin it.
    private let now: Date
    private let calendar: Calendar

    @State private var customDate: Date
    #if os(macOS)
    @State private var isCustomExpanded = false
    #else
    @State private var detent: PresentationDetent = .medium
    #endif

    /// - Parameters:
    ///   - header: The message being snoozed; its subject is shown for context.
    ///   - sourceID: Source (account and mailbox) the message belongs to.
    ///   - now: Reference time for resolving the quick options.
    ///   - calendar: Calendar and time zone used for day arithmetic.
    ///   - onConfirm: Called with the chosen wake time.
    ///   - onCancel: Called when the sheet is dismissed without a choice.
    init(
        header: MessageHeader,
        sourceID: MailSourceID?,
        now: Date = Date(),
        calendar: Calendar = .current,
        onConfirm: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.header = header
        self.sourceID = sourceID
        self.now = now
        self.calendar = calendar
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _customDate = State(initialValue: now.addingTimeInterval(3 * 3600))
    }

    var body: some View {
        #if os(iOS)
        iOSBody
        #else
        macOSBody
        #endif
    }
}

private extension SnoozeQuickOption {
    var title: String {
        switch self {
        case .laterToday: return String(localized: "laterToday.lower", bundle: .module)
        case .thisEvening: return String(localized: "This evening", bundle: .module)
        case .tomorrowMorning: return String(localized: "Tomorrow morning", bundle: .module)
        case .thisWeekend: return String(localized: "This weekend", bundle: .module)
        case .nextWeek: return String(localized: "nextWeek.lower", bundle: .module)
        }
    }

    var symbolName: String {
        switch self {
        case .laterToday: return "clock"
        case .thisEvening: return "moon"
        case .tomorrowMorning: return "sunrise"
        case .thisWeekend: return "sofa"
        case .nextWeek: return "calendar.badge.plus"
        }
    }
}

// MARK: - iOS

#if os(iOS)
extension SnoozePickerView {
    private enum Route: Hashable {
        case customDate
    }

    private var iOSBody: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SnoozeSchedule.suggestions(now: now, calendar: calendar)) { suggestion in
                        quickRow(suggestion)
                    }
                } header: {
                    Text(header.subject)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .textCase(nil)
                        .lineLimit(2)
                }

                Section {
                    NavigationLink(value: Route.customDate) {
                        HStack(spacing: BrevSpacing.md) {
                            rowIcon("calendar")
                            Text("Choose date & time…", bundle: .module)
                                .brevFont(.body)
                                .foregroundStyle(theme.textPrimary.color)
                        }
                        .frame(minHeight: 44)
                    }
                    .listRowBackground(theme.bgSecondary.color)
                    .listRowSeparatorTint(theme.separator.color)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.bgPrimary.color)
            .navigationTitle(Text("snooze.action", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.bgPrimary.color, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                }
            }
            .navigationDestination(for: Route.self) { _ in
                customDateScreen
            }
        }
        .tint(theme.accent.color)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bgPrimary.color)
        .onAppear {
            // The quick options don't fit the medium detent at accessibility sizes.
            if dynamicTypeSize.isAccessibilitySize { detent = .large }
        }
    }

    private func rowIcon(_ symbolName: String) -> some View {
        Image(systemName: symbolName)
            .foregroundStyle(theme.accent.color)
            .frame(width: Self.iconWidth)
            .accessibilityHidden(true)
    }

    private static let iconWidth: CGFloat = 28

    private func quickRow(_ suggestion: SnoozeSuggestion) -> some View {
        let option = suggestion.option
        let visual = SnoozeSchedule.label(
            for: suggestion.wakeDate, now: now, calendar: calendar, locale: locale, style: .compact
        )
        let spoken = SnoozeSchedule.label(
            for: suggestion.wakeDate, now: now, calendar: calendar, locale: locale, style: .spoken
        )
        return Button {
            onConfirm(suggestion.wakeDate)
        } label: {
            // The wake time drops under the title when the row runs out of room
            // (accessibility Dynamic Type sizes).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrevSpacing.md) {
                    rowIcon(option.symbolName)
                    Text(option.title)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer(minLength: BrevSpacing.sm)
                    Text(visual)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                }
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    HStack(spacing: BrevSpacing.md) {
                        rowIcon(option.symbolName)
                        Text(option.title)
                            .brevFont(.body)
                            .foregroundStyle(theme.textPrimary.color)
                    }
                    Text(visual)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                        .padding(.leading, Self.iconWidth + BrevSpacing.md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
        }
        .listRowBackground(theme.bgSecondary.color)
        .listRowSeparatorTint(theme.separator.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.title), \(spoken)")
        .accessibilityAddTraits(.isButton)
    }

    private var customDateScreen: some View {
        List {
            Section {
                DatePicker(
                    String(localized: "Date", bundle: .module),
                    selection: $customDate,
                    in: now...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .listRowBackground(theme.bgSecondary.color)
            }

            Section {
                DatePicker(
                    String(localized: "Time", bundle: .module),
                    selection: $customDate,
                    in: now...,
                    displayedComponents: .hourAndMinute
                )
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .frame(minHeight: 44)
                .listRowBackground(theme.bgSecondary.color)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.bgPrimary.color)
        .navigationTitle(Text("Date & Time", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.bgPrimary.color, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "snooze.action", bundle: .module)) {
                    onConfirm(customDate)
                }
                .fontWeight(.semibold)
                .disabled(!SnoozeSchedule.isValidCustomWake(customDate, now: now))
            }
        }
        .onAppear { detent = .large }
        .onDisappear { detent = dynamicTypeSize.isAccessibilitySize ? .large : .medium }
    }
}
#endif

// MARK: - macOS

#if os(macOS)
extension SnoozePickerView {
    private var macOSBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "moon.zzz").foregroundStyle(theme.accent.color)
                Text("Snooze Message", bundle: .module)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary.color)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(BrevSpacing.md)

            BrevDivider()

            Text(header.subject)
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(2)
                .padding(.horizontal, BrevSpacing.md)
                .padding(.vertical, BrevSpacing.sm)

            BrevDivider()

            VStack(spacing: 0) {
                ForEach(SnoozeSchedule.suggestions(now: now, calendar: calendar, includeExtended: false)) { suggestion in
                    quickRow(suggestion)
                    BrevDivider()
                }
                customRow
            }
        }
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }

    private func quickRow(_ suggestion: SnoozeSuggestion) -> some View {
        Button {
            onConfirm(suggestion.wakeDate)
        } label: {
            HStack(spacing: BrevSpacing.md) {
                Image(systemName: suggestion.option.symbolName)
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 24)
                Text(suggestion.option.title)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
                Text(suggestion.wakeDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(suggestion.wakeDate.formatted(.dateTime.weekday(.wide).hour().minute()))
    }

    @ViewBuilder
    private var customRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCustomExpanded.toggle()
            }
        } label: {
            HStack(spacing: BrevSpacing.md) {
                Image(systemName: "calendar")
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 24)
                Text("Custom date & time", bundle: .module)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
                Image(systemName: isCustomExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            isCustomExpanded
                ? String(localized: "Expanded", bundle: .module)
                : String(localized: "Collapsed", bundle: .module)
        )
        .accessibilityHint(
            String(localized: "Shows a date picker for a custom wake time", bundle: .module)
        )

        if isCustomExpanded {
            DatePicker(
                String(localized: "Wake at", bundle: .module),
                selection: $customDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .padding(BrevSpacing.md)

            BrevButton("Snooze Until Selected Time", style: .primary, bundle: .module) {
                onConfirm(customDate)
            }
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, BrevSpacing.md)
            .padding(.bottom, BrevSpacing.md)
        }
    }
}
#endif
