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

/// Settings sheet for picking one of the built-in themes.
///
/// Writes the chosen theme back through the `onSelect` closure; the
/// parent scene is responsible for re-injecting it via
/// `.brevTheme(_:)`.
public struct ThemePickerView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    private let themes: [BrevTheme]
    private let onClose: (() -> Void)?
    private let onSelect: (BrevTheme) -> Void

    public init(
        themes: [BrevTheme] = BrevTheme.brevBuiltIns,
        onClose: (() -> Void)? = nil,
        onSelect: @escaping (BrevTheme) -> Void
    ) {
        self.themes = themes
        self.onClose = onClose
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Text("Theme", bundle: .module)
                .brevFont(.title)
                .foregroundStyle(theme.textPrimary.color)

            VStack(spacing: BrevSpacing.xs) {
                ForEach(themes) { candidate in
                    Button {
                        onSelect(candidate)
                        close()
                    } label: {
                        ThemeRow(
                            candidate: candidate,
                            isSelected: candidate.id == theme.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                BrevButton("Done", style: .secondary) { close() }
            }
            .padding(.top, BrevSpacing.sm)
        }
        .padding(BrevSpacing.lg)
        .frame(minWidth: 320, idealWidth: 380)
        .background(BrevWindowSurfaceBackground(role: .utility))
        .brevWindowTranslucency(windowRole: .utility)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

private struct ThemeRow: View {
    @Environment(\.brevTheme) private var theme
    let candidate: BrevTheme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrevSpacing.md) {
            swatch
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(candidate.name)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(candidate.mode == .dark ? "Dark" : "Light")
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.accent.color)
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(isSelected ? theme.selection.color : theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
        .contentShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var swatch: some View {
        HStack(spacing: 0) {
            candidate.bgPrimary.color
            candidate.accent.color
            candidate.textPrimary.color
        }
        .frame(width: 48, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .stroke(theme.border.color, lineWidth: 1)
        )
    }
}
