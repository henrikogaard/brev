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
struct SnoozePickerView: View {
    @Environment(\.brevTheme) private var theme

    let header: MessageHeader
    let sourceID: MailSourceID?
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @State private var customDate = Date().addingTimeInterval(3 * 3600)
    @State private var isCustomExpanded = false

    private enum QuickOption: String, CaseIterable, Identifiable {
        case laterToday, tomorrowMorning, nextWeek, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .laterToday: return "Later Today (+3h)"
            case .tomorrowMorning: return "Tomorrow Morning (9am)"
            case .nextWeek: return "Next Week"
            case .custom: return "Custom Date & Time"
            }
        }

        var symbolName: String {
            switch self {
            case .laterToday: return "clock"
            case .tomorrowMorning: return "sunrise"
            case .nextWeek: return "calendar.badge.plus"
            case .custom: return "calendar"
            }
        }

        func wakeDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
            switch self {
            case .laterToday:
                return calendar.date(byAdding: .hour, value: 3, to: now)
            case .tomorrowMorning:
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
            case .nextWeek:
                guard let week = calendar.date(byAdding: .weekOfYear, value: 1, to: now) else { return nil }
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: week)
            case .custom:
                return nil
            }
        }
    }

    var body: some View {
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
                ForEach(QuickOption.allCases) { option in
                    if option == .custom {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCustomExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: BrevSpacing.md) {
                                Image(systemName: option.symbolName)
                                    .foregroundStyle(theme.accent.color)
                                    .frame(width: 24)
                                Text(option.title)
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
                                String(localized: "Wake at", bundle: .module),
                                selection: $customDate,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .padding(BrevSpacing.md)

                            BrevButton("Snooze Until Selected Time", style: .primary) {
                                onConfirm(customDate)
                            }
                            .padding(.horizontal, BrevSpacing.md)
                            .padding(.bottom, BrevSpacing.md)
                        }
                    } else {
                        Button {
                            if let date = option.wakeDate() { onConfirm(date) }
                        } label: {
                            HStack(spacing: BrevSpacing.md) {
                                Image(systemName: option.symbolName)
                                    .foregroundStyle(theme.accent.color)
                                    .frame(width: 24)
                                Text(option.title)
                                    .brevFont(.body)
                                    .foregroundStyle(theme.textPrimary.color)
                                Spacer()
                                if let wake = option.wakeDate() {
                                    Text(wake.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                        .brevFont(.caption)
                                        .foregroundStyle(theme.textTertiary.color)
                                }
                            }
                            .padding(.horizontal, BrevSpacing.md)
                            .padding(.vertical, BrevSpacing.sm)
                        }
                        .buttonStyle(.plain)
                        BrevDivider()
                    }
                }
            }
        }
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }
}
