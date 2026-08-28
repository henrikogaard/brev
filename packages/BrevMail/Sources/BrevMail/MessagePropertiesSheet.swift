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

/// Read-only inspector for a single message's metadata. Presented from the
/// "Properties…" context-menu action. All fields come from the loaded
/// `MessageHeader`, so the sheet works offline and in demo mode without a
/// backend round-trip.
struct MessagePropertiesSheet: View {
    @Environment(\.brevTheme) private var theme
    let header: MessageHeader
    let onClose: () -> Void

    private var rows: [MessagePropertyRow] {
        MessagePropertiesPresentation.rows(
            for: header,
            dateText: MessagePropertiesPresentation.dateText(for: header.date)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            BrevDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    ForEach(rows) { row in
                        field(label: row.label, value: row.value)
                    }
                }
                .padding(BrevSpacing.md)
            }
        }
        .frame(minWidth: 360, idealWidth: 440, minHeight: 320, idealHeight: 420)
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }

    private var titleBar: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(theme.accent.color)
            Text("Message Properties", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    private func field(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(label)
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textSecondary.color)
            Text(value)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
