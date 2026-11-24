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

/// Collapsible, non-editable footer shown below the compose body editor when a
/// reopened draft carries preserved quoted HTML (nested/styled blockquotes,
/// Gmail `.gmail_quote`, Outlook `#divRplyFwdMsg`, or webmail tables) that must
/// stay intact byte-for-byte on save and send.
struct ComposePreservedQuoteSection: View {
    @Environment(\.brevTheme) private var theme
    @StateObject private var previewWebViewStore = HTMLBodyWebViewStore()
    @State private var isExpanded: Bool

    let preservedQuotedHTML: String
    let inheritedDirection: String?
    let stripTrackingPixels: Bool
    let fontFamily: MailboxFontFamily
    let textSize: MailboxTextSize
    let renderingMode: HTMLBodyRenderingMode

    init(
        preservedQuotedHTML: String,
        inheritedDirection: String? = nil,
        stripTrackingPixels: Bool = true,
        fontFamily: MailboxFontFamily = .system,
        textSize: MailboxTextSize = .medium,
        renderingMode: HTMLBodyRenderingMode = .original,
        initiallyExpanded: Bool = false
    ) {
        self.preservedQuotedHTML = preservedQuotedHTML
        self.inheritedDirection = inheritedDirection
        self.stripTrackingPixels = stripTrackingPixels
        self.fontFamily = fontFamily
        self.textSize = textSize
        self.renderingMode = renderingMode
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrevDivider()

            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: BrevSpacing.sm) {
                    Image(systemName: "text.quote")
                        .font(.footnote)
                        .foregroundStyle(theme.accent.color)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quoted message preserved", bundle: .module)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textPrimary.color)
                            .lineLimit(1)

                        Text("Kept intact when saving or sending", bundle: .module)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .lineLimit(1)
                    }

                    Spacer(minLength: BrevSpacing.sm)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textTertiary.color)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, BrevSpacing.xl)
                .padding(.vertical, BrevSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("brev-compose-preserved-quote-toggle")
            .accessibilityLabel(
                isExpanded
                    ? String(localized: "Hide quoted message", bundle: .module)
                    : String(localized: "Show quoted message", bundle: .module)
            )
            .accessibilityHint(String(localized: "Kept intact when saving or sending", bundle: .module))

            if isExpanded {
                ScrollView {
                    HTMLBodyWebView(
                        store: previewWebViewStore,
                        html: ComposeHTMLPreviewSource.sanitizedQuotePreviewHTML(
                            preservedQuotedHTML,
                            inheritedDirection: inheritedDirection
                        ),
                        allowRemoteContent: false,
                        stripTrackingPixels: stripTrackingPixels,
                        fontFamily: fontFamily,
                        textSize: textSize,
                        renderingMode: renderingMode,
                        onOpenURL: { _ in }
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(BrevSpacing.md)
                }
                .frame(maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                        .fill(theme.bgSecondary.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                        .strokeBorder(theme.border.color, lineWidth: 0.5)
                )
                .padding(.horizontal, BrevSpacing.xl)
                .padding(.bottom, BrevSpacing.md)
            }
        }
    }
}
