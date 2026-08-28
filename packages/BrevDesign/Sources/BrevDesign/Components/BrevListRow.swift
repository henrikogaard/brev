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

/// A themed list row that emphasizes a primary title with an optional
/// trailing accessory and selection background.
///
/// This is BrevDesign's neutral wrapper around an `HStack`; specific
/// row types (message-list row, settings row) compose this rather
/// than each rolling its own selection treatment.
public struct BrevListRow<Leading: View, Trailing: View>: View {
    @Environment(\.brevTheme) private var theme

    private let title: String
    private let subtitle: String?
    private let isSelected: Bool
    private let leading: Leading
    private let trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: BrevSpacing.md) {
            leading
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: BrevSpacing.sm)
            trailing
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(isSelected ? theme.selection.color : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
        .contentShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }
}
