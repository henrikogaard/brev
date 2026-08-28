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

/// Explains why an attachment search may fetch message data while it runs.
struct AttachmentSearchDisclosureView: View {
    @Environment(\.brevTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent.color)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text("Searching attachments", bundle: .module)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(
                    "Brev checks message contents page by page; this may fetch message data because you asked for an attachment search. No background fetch is running.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}
