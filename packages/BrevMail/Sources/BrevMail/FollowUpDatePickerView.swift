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
    @State private var isCustomExpanded = false

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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "flag").foregroundStyle(theme.warning.color)
                Text(String(localized: "Follow Up", bundle: .module))
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary.color)
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
                                .foregroundStyle(theme.warning.color)
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
                    }
                    .buttonStyle(.plain)
                    BrevDivider()
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCustomExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: BrevSpacing.md) {
                        Image(systemName: "calendar")
                            .foregroundStyle(theme.warning.color)
                            .frame(width: 24)
                        Text(String(localized: "Custom Date & Time", bundle: .module))
                            .brevFont(.body)
                            .foregroundStyle(theme.textPrimary.color)
                        Spacer()
                        Image(systemName: isCustomExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(theme.textTertiary.color)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.vertical, BrevSpacing.sm)
                }
                .buttonStyle(.plain)

                if isCustomExpanded {
                    DatePicker(
                        String(localized: "Follow-up date", bundle: .module),
                        selection: $customDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .padding(BrevSpacing.md)

                    BrevButton(String(localized: "Set Follow-Up Reminder", bundle: .module), style: .primary) {
                        onConfirm(customDate)
                    }
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

    private func presetSymbol(_ preset: FollowUpReminderPreset) -> String {
        switch preset {
        case .laterToday: return "clock"
        case .tomorrow: return "sunrise"
        case .nextWeek: return "calendar.badge.plus"
        }
    }
}
