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

import BrevThemes
import SwiftUI

/// Semantic style for `BrevStatusBanner`.
///
/// Each case maps to an existing theme semantic token; no literal
/// colors are used. Per ADR-0028 invariant 3.
public enum BrevStatusBannerStyle: Sendable, Hashable, CaseIterable {
    /// Neutral informational state.
    case info
    /// Recoverable warning — something may need attention.
    case warning
    /// Error state — an operation failed.
    case error
    /// Positive confirmation — an operation succeeded.
    case success

    var symbolName: String {
        switch self {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        case .success:
            return "checkmark.circle"
        }
    }

    func accentColor(in theme: BrevTheme) -> Color {
        switch self {
        case .info:
            return theme.info.color
        case .warning:
            return theme.warning.color
        case .error:
            return theme.danger.color
        case .success:
            return theme.success.color
        }
    }

    func backgroundColor(in theme: BrevTheme) -> Color {
        // Muted version of the semantic accent so the banner doesn't
        // visually compete with the main content reading area.
        switch self {
        case .info:
            return theme.info.color.opacity(0.08)
        case .warning:
            return theme.warning.color.opacity(0.08)
        case .error:
            return theme.danger.color.opacity(0.08)
        case .success:
            return theme.success.color.opacity(0.08)
        }
    }
}

/// In-content horizontal banner for non-blocking status messages.
///
/// Place in a `safeAreaInset`, list footer, or below a toolbar. Each
/// style maps to a semantic theme token — no literal colors. Per
/// ADR-0013 and ADR-0002.
///
/// - Parameters:
///   - style: Semantic tone of the banner.
///   - title: Primary status label.
///   - message: Optional supplementary description shown below the title.
///   - action: Optional inline action button with a label and handler.
///   - bundle: Bundle that holds the String Catalog for the labels. Pass the
///     owning package's `Bundle.module` when the labels are declared in a
///     Swift package; the default keeps app-target call sites on the normal
///     main-bundle lookup path.
public struct BrevStatusBanner: View {
    @Environment(\.brevTheme) private var theme
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 20
    @ScaledMetric(relativeTo: .footnote) private var actionHeight: CGFloat = 44

    private let style: BrevStatusBannerStyle
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let actionLabel: LocalizedStringKey?
    private let actionHandler: (() -> Void)?
    private let bundle: Bundle?

    public init(
        style: BrevStatusBannerStyle = .info,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        action: (label: LocalizedStringKey, handler: () -> Void)? = nil,
        bundle: Bundle? = nil
    ) {
        self.style = style
        self.title = title
        self.message = message
        self.bundle = bundle
        actionLabel = action?.label
        actionHandler = action?.handler
    }

    public var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.md) {
            Image(systemName: style.symbolName)
                .foregroundStyle(style.accentColor(in: theme))
                .brevFont(.subheadline)
                .frame(minWidth: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title, bundle: bundle)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)

                if let message {
                    Text(message, bundle: bundle)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionLabel, let actionHandler {
                    Button(action: actionHandler) { Text(actionLabel, bundle: bundle) }
                        .buttonStyle(.borderless)
                        .brevFont(.footnote)
                        // Action text is body-size interactive text: the tinted
                        // status colors are only guaranteed 3:1 (success, info),
                        // so the action uses the theme accent (>= 4.5:1).
                        .foregroundStyle(theme.accent.color)
                        .modifier(ActionHitArea(scaledHeight: actionHeight))
                }
            }

            Spacer(minLength: BrevSpacing.sm)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.backgroundColor(in: theme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.accentColor(in: theme).opacity(0.25))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Gives the inline action a 44 pt (Dynamic Type scaled) touch target on iOS;
/// macOS keeps the compact inline link.
private struct ActionHitArea: ViewModifier {
    let scaledHeight: CGFloat

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .frame(minHeight: BrevHitTarget.resolved(scaled: scaledHeight), alignment: .leading)
            .contentShape(Rectangle())
        #else
        content
        #endif
    }
}
