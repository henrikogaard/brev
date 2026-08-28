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
import Foundation
import SwiftUI

/// Visual variant of `BrevButton`.
public enum BrevButtonStyle: Sendable, Hashable {
    /// Filled accent button — main CTAs (e.g. Send).
    case primary
    /// Outline button — secondary actions (Cancel, Save Draft).
    case secondary
    /// Borderless tinted-text button — tertiary actions in toolbars.
    case tertiary
    /// Filled danger button — destructive confirmations.
    case destructive
}

/// Brev's primary button primitive.
///
/// Always pulls colors from the environment theme. Per ADR-0028
/// invariant 3, views must not introduce literal colors — this
/// component is the only sanctioned way to express "the button color"
/// in user-facing surfaces.
public struct BrevButton: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private enum Title {
        case localized(LocalizedStringKey, bundle: Bundle?)
        case verbatim(String)
    }

    private let title: Title
    private let style: BrevButtonStyle
    private let action: () -> Void

    /// Creates a button whose static title participates in String Catalog
    /// extraction and runtime localization.
    ///
    /// Pass the owning package's `Bundle.module` when the title is declared
    /// in a Swift package. The default keeps app-target call sites on the
    /// normal main-bundle lookup path.
    public init(
        _ title: LocalizedStringKey,
        style: BrevButtonStyle = .primary,
        bundle: Bundle? = nil,
        action: @escaping () -> Void
    ) {
        self.title = .localized(title, bundle: bundle)
        self.style = style
        self.action = action
    }

    /// Creates a button with runtime-generated text that must not be treated
    /// as a localization key (for example, an email address or provider name).
    public init(
        verbatim title: String,
        style: BrevButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = .verbatim(title)
        self.style = style
        self.action = action
    }

    /// Compatibility overload for existing pre-localized strings. New
    /// runtime-generated titles should use the labeled `verbatim:` form so
    /// callers make the non-localized intent explicit.
    @_disfavoredOverload
    public init(
        _ title: String,
        style: BrevButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.init(verbatim: title, style: style, action: action)
    }

    public var body: some View {
        Button(action: action) {
            Group {
                switch title {
                case .localized(let title, let bundle):
                    Text(title, bundle: bundle)
                case .verbatim(let title):
                    Text(verbatim: title)
                }
            }
            .brevFont(.headline)
            .padding(.horizontal, BrevSpacing.lg)
            .padding(.vertical, BrevSpacing.sm)
            .frame(minHeight: 32)
            .background(background)
            .foregroundStyle(foreground)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
            .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            theme.accent.color
        case .destructive:
            theme.danger.color
        case .secondary, .tertiary:
            Color.clear
        }
    }

    private var foreground: Color {
        switch style {
        case .primary, .destructive:
            return theme.bgPrimary.color
        case .secondary:
            return theme.textPrimary.color
        case .tertiary:
            return theme.accent.color
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .secondary:
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color, lineWidth: 1)
        case .primary, .destructive, .tertiary:
            EmptyView()
        }
    }
}
