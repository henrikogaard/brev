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

enum SettingsCalloutTone {
    case info
    case success
    case warning

    var symbolColor: KeyPath<BrevTheme, BrevColor> {
        switch self {
        case .info: return \.info
        case .success: return \.success
        case .warning: return \.warning
        }
    }
}

/// A titled group of settings rows.
///
/// The header and rows share one continuous surface. Proximity, indentation,
/// and the spacing scale express the group without wrapping every section in
/// another rounded card.
struct SettingsGroup<Content: View>: View {
    @Environment(\.brevTheme) private var theme
    let title: String
    let subtitle: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .top, spacing: BrevSpacing.sm) {
                SettingsSymbol(symbolName: symbolName)
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(title)
                        .brevFont(.headline)
                        .foregroundStyle(theme.textPrimary.color)
                    Text(subtitle)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Settings is a continuous task surface. Proximity and alignment
            // carry the grouping so every section does not become another card.
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, BrevSpacing.xl)
            .padding(.top, BrevSpacing.xs)
        }
        .padding(.bottom, BrevSpacing.sm)
    }
}

struct SettingsToggleRow: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        // A macOS switch hugs its label, so without the greedy frame each
        // row's switch landed just after its own text — every row at a
        // different x, and none lined up with the pickers beside them.
        Toggle(isOn: $isOn) {
            SettingsRowLabel(
                symbolName: symbolName,
                title: title,
                subtitle: subtitle
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(theme.accent.color)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String
    let title: String
    let subtitle: String
    @Binding var selection: Selection
    var selectionTitle: String?
    @ViewBuilder let content: Content

    init(
        symbolName: String,
        title: String,
        subtitle: String,
        selection: Binding<Selection>,
        selectionTitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        _selection = selection
        self.selectionTitle = selectionTitle
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                SettingsRowLabel(
                    symbolName: symbolName,
                    title: title,
                    subtitle: subtitle
                )
                Spacer(minLength: BrevSpacing.md)
                picker
                    .frame(maxWidth: 220)
            }

            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                SettingsRowLabel(
                    symbolName: symbolName,
                    title: title,
                    subtitle: subtitle
                )
                picker
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let selectionTitle {
            pickerContent.accessibilityValue(selectionTitle)
        } else {
            pickerContent
        }
    }

    private var pickerContent: some View {
        ZStack(alignment: .trailing) {
            Picker(title, selection: $selection) {
                content
            }
            .labelsHidden()
            .opacity(selectionTitle == nil ? 1 : 0.01)

            if let selectionTitle {
                HStack(spacing: BrevSpacing.xs) {
                    Text(selectionTitle)
                        .brevFont(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .brevFont(.caption)
                }
                .foregroundStyle(theme.textPrimary.color)
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, BrevSpacing.xs)
                .background(theme.bgSecondary.color.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: BrevRadius.sm)
                        .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

struct SettingsSegmentedRow<Selection: Hashable, Content: View>: View {
    let symbolName: String
    let title: String
    let subtitle: String
    @Binding var selection: Selection
    var isEnabled = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            SettingsRowLabel(
                symbolName: symbolName,
                title: title,
                subtitle: subtitle
            )
            Picker(title, selection: $selection) {
                content
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!isEnabled)
        }
        .opacity(isEnabled ? 1 : 0.55)
    }
}

struct SettingsInfoCallout: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String
    let message: String
    let tone: SettingsCalloutTone

    var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(theme[keyPath: tone.symbolColor].color)
                .frame(width: 18)
            Text(message)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrevSpacing.sm)
        .background(theme.bgSecondary.color.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .stroke(theme.border.color.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct SettingsRowLabel: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.md) {
            SettingsSymbol(symbolName: symbolName)
            // `.body` is the token's documented size for settings rows.
            // These were a step down at `.subheadline`, which left the
            // controls reading as secondary to the sidebar next to them.
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Text(subtitle)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsSymbol: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.accent.color)
            .frame(width: 18)
    }
}
