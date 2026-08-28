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

/// A theme-aware placeholder block used while real content loads.
public struct BrevSkeletonBlock: View {
    @Environment(\.brevTheme) private var theme

    private let width: CGFloat?
    private let height: CGFloat
    private let cornerRadius: CGFloat

    public init(
        width: CGFloat? = nil,
        height: CGFloat,
        cornerRadius: CGFloat = BrevRadius.sm
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(theme.bgSecondary.color)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(theme.border.color.opacity(0.55), lineWidth: 0.5)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// Placeholder rows shaped like the desktop message list.
public struct BrevSkeletonList: View {
    private let rowCount: Int

    public init(rowCount: Int = 6) {
        self.rowCount = max(1, rowCount)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< rowCount, id: \.self) { index in
                BrevSkeletonRow(index: index)
                if index < rowCount - 1 {
                    BrevDivider()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading messages", bundle: .module))
    }
}

/// Placeholder text block for reading-pane body loads.
public struct BrevSkeletonText: View {
    private let lineCount: Int
    private let lineHeight: CGFloat

    public init(lineCount: Int = 6, lineHeight: CGFloat = 12) {
        self.lineCount = max(1, lineCount)
        self.lineHeight = lineHeight
    }

    public var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                ForEach(0 ..< lineCount, id: \.self) { index in
                    BrevSkeletonBlock(
                        width: proxy.size.width * Self.widthFraction(for: index),
                        height: lineHeight,
                        cornerRadius: BrevRadius.pill
                    )
                }
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading message body", bundle: .module))
    }

    private var totalHeight: CGFloat {
        let lineSpacing = CGFloat(max(0, lineCount - 1)) * BrevSpacing.sm
        return CGFloat(lineCount) * lineHeight + lineSpacing
    }

    private static func widthFraction(for index: Int) -> CGFloat {
        switch index % 4 {
        case 1:
            return 0.82
        case 2:
            return 0.94
        case 3:
            return 0.64
        default:
            return 1.0
        }
    }
}

private struct BrevSkeletonRow: View {
    fileprivate let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.md) {
            BrevSkeletonBlock(
                width: 36,
                height: 36,
                cornerRadius: BrevRadius.pill
            )

            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                HStack {
                    BrevSkeletonBlock(width: subjectWidth, height: 12, cornerRadius: BrevRadius.pill)
                    Spacer(minLength: BrevSpacing.lg)
                    BrevSkeletonBlock(width: 44, height: 10, cornerRadius: BrevRadius.pill)
                }
                BrevSkeletonBlock(width: senderWidth, height: 10, cornerRadius: BrevRadius.pill)
                BrevSkeletonBlock(height: 10, cornerRadius: BrevRadius.pill)
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    private var subjectWidth: CGFloat {
        switch index % 3 {
        case 1:
            return 168
        case 2:
            return 132
        default:
            return 204
        }
    }

    private var senderWidth: CGFloat {
        switch index % 3 {
        case 1:
            return 92
        case 2:
            return 124
        default:
            return 108
        }
    }
}
