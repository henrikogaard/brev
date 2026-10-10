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
import BrevSettings
import BrevThemes
import SwiftUI

/// Sheet for picking a follow-up reminder date on a message.
struct FollowUpDatePickerView: View {
    @Environment(\.brevTheme) private var theme

    let header: MessageHeader
    let sourceID: MailSourceID?
    let existingReminder: FollowUpReminder?
    let onConfirm: (Date) -> Void
    let onRemove: (() -> Void)?
    let onCancel: () -> Void

    @State private var customDate = Date().addingTimeInterval(86400)
    #if os(macOS)
    @State private var isCustomExpanded = false
    #else
    @State private var detent: PresentationDetent = .medium
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    #endif

    init(
        header: MessageHeader,
        sourceID: MailSourceID?,
        existingReminder: FollowUpReminder? = nil,
        onConfirm: @escaping (Date) -> Void,
        onRemove: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.header = header
        self.sourceID = sourceID
        self.existingReminder = existingReminder
        self.onConfirm = onConfirm
        self.onRemove = onRemove
        self.onCancel = onCancel
        _customDate = State(initialValue: existingReminder?.dueAt ?? Date().addingTimeInterval(86400))
    }

    var body: some View {
        #if os(iOS)
        nativeBody
        #else
        desktopBody
        #endif
    }

    #if os(iOS)
    /// iOS: an inset-grouped list under a standard navigation bar; presets
    /// confirm on tap like the snooze sheet.
    private var nativeBody: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FollowUpReminderPreset.allCases) { preset in
                        presetRow(preset)
                    }
                } header: {
                    Text(header.subject)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .textCase(nil)
                        .lineLimit(2)
                }

                Section {
                    DatePicker(
                        String(localized: "Follow-up date", bundle: .module),
                        selection: $customDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .brevFont(.body)
                    .brevSheetRow()
                    Button {
                        onConfirm(customDate)
                    } label: {
                        Text("Set Follow-Up Reminder", bundle: .module)
                            .brevFont(.body)
                    }
                    .brevSheetRow()
                } header: {
                    Text("Custom date & time", bundle: .module)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .textCase(nil)
                }

                if existingReminder != nil, let onRemove {
                    Section {
                        Button(role: .destructive) {
                            onRemove()
                        } label: {
                            Text("Remove Follow-Up Reminder", bundle: .module)
                                .brevFont(.body)
                                .foregroundStyle(theme.danger.color)
                        }
                        .brevSheetRow()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Follow Up", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear {
            // The presets and custom picker do not fit the medium detent at
            // accessibility sizes.
            if dynamicTypeSize.isAccessibilitySize { detent = .large }
        }
    }

    private func presetRow(_ preset: FollowUpReminderPreset) -> some View {
        let dueAt = FollowUpReminderPresentation.dueAt(for: preset)
        let visual = dueAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return Button {
            onConfirm(dueAt)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrevSpacing.md) {
                    presetIcon(preset)
                    Text(preset.title)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: BrevSpacing.sm)
                    Text(visual)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textSecondary.color)
                }
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    HStack(spacing: BrevSpacing.md) {
                        presetIcon(preset)
                        Text(preset.title)
                            .brevFont(.body)
                            .foregroundStyle(theme.textPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(visual)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textSecondary.color)
                        .padding(.leading, iconWidth + BrevSpacing.md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .brevSheetRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preset.title)
        .accessibilityValue(dueAt.formatted(.dateTime.weekday(.wide).hour().minute()))
        .accessibilityAddTraits(.isButton)
    }

    private func presetIcon(_ preset: FollowUpReminderPreset) -> some View {
        Image(systemName: presetSymbol(preset))
            .foregroundStyle(theme.accent.color)
            .frame(width: iconWidth)
            .accessibilityHidden(true)
    }
    #endif

    #if os(macOS)
    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "flag").foregroundStyle(theme.accent.color)
                Text(String(localized: "Follow Up", bundle: .module))
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
                ForEach(FollowUpReminderPreset.allCases) { preset in
                    Button {
                        onConfirm(FollowUpReminderPresentation.dueAt(for: preset))
                    } label: {
                        HStack(spacing: BrevSpacing.md) {
                            Image(systemName: presetSymbol(preset))
                                .foregroundStyle(theme.accent.color)
                                .frame(width: 24)
                            Text(preset.title)
                                .brevFont(.body)
                                .foregroundStyle(theme.textPrimary.color)
                            Spacer()
                            Text(FollowUpReminderPresentation.dueAt(for: preset)
                                .formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                .brevFont(.caption)
                                .foregroundStyle(theme.textTertiary.color)
                        }
                        .padding(.horizontal, BrevSpacing.md)
                        .padding(.vertical, BrevSpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        FollowUpReminderPresentation.dueAt(for: preset)
                            .formatted(.dateTime.weekday(.wide).hour().minute())
                    )
                    BrevDivider()
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCustomExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: BrevSpacing.md) {
                        Image(systemName: "calendar")
                            .foregroundStyle(theme.accent.color)
                            .frame(width: 24)
                        Text(String(localized: "Custom date & time", bundle: .module))
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
                    String(localized: "Shows a date picker for a custom reminder time", bundle: .module)
                )

                if isCustomExpanded {
                    DatePicker(
                        String(localized: "Follow-up date", bundle: .module),
                        selection: $customDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .padding(BrevSpacing.md)

                    BrevButton("Set Follow-Up Reminder", style: .primary, bundle: .module) {
                        onConfirm(customDate)
                    }
                    .keyboardShortcut(.defaultAction)
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.bottom, BrevSpacing.md)
                }

                if existingReminder != nil, let onRemove {
                    BrevButton(String(localized: "Remove Follow-Up Reminder", bundle: .module), style: .tertiary) {
                        onRemove()
                    }
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.bottom, BrevSpacing.md)
                }
            }
        }
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }

    #endif

    private func presetSymbol(_ preset: FollowUpReminderPreset) -> String {
        switch preset {
        case .laterToday: return "clock"
        case .tomorrow: return "sunrise"
        case .nextWeek: return "calendar.badge.plus"
        }
    }
}
