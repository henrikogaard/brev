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

struct ScheduledOutboxRow: View {
    @Environment(\.brevTheme) private var theme
    let entry: PendingScheduledSend
    let isBusy: Bool
    let canEdit: Bool
    let onChange: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.subject.isEmpty ? String(localized: "Scheduled message", bundle: .module) : entry.subject)
                    .brevFont(.subheadline).fontWeight(.medium).foregroundStyle(theme.textPrimary.color).lineLimit(2)
                Spacer(minLength: BrevSpacing.sm)
                Text(status).brevFont(.caption).foregroundStyle(theme.textSecondary.color)
            }
            Text(entry.scheduledFor, format: .dateTime.month(.abbreviated).day().hour().minute())
                .brevFont(.caption).foregroundStyle(theme.textSecondary.color)
            if let error = entry.lastError {
                Text(error).brevFont(.caption).foregroundStyle(theme.textSecondary.color).lineLimit(3).help(error)
            }
            if let retry = entry.nextAttemptAt, entry.state == .waiting {
                Text("Next attempt: \(retry.formatted(date: .abbreviated, time: .shortened))", bundle: .module)
                    .brevFont(.caption).foregroundStyle(theme.textSecondary.color)
            }
            if canEdit {
                HStack(spacing: BrevSpacing.md) {
                    Button(action: onChange) {
                        Text(entry.state == .needsReview ? String(localized: "Review and retry…", bundle: .module)
                            : String(localized: "Change time…", bundle: .module))
                            .modifier(ScheduledActionTarget())
                    }
                    Button(action: onCancel) {
                        Text("Cancel schedule", bundle: .module).modifier(ScheduledActionTarget())
                    }
                }
                .controlSize(.small)
                .disabled(isBusy || entry.state == .delivering)
            }
        }
        .padding(.vertical, BrevSpacing.xs)
    }

    private var status: String {
        switch entry.state {
        case .waiting: String(localized: "Waiting", bundle: .module)
        case .delivering: String(localized: "Delivering", bundle: .module)
        case .needsReview: String(localized: "Needs review", bundle: .module)
        }
    }
}

private struct ScheduledActionTarget: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.frame(minHeight: 44)
        #else
        content
        #endif
    }
}
