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

/// Shared "quiet card" inset surface: a faint secondary fill with a hairline
/// border, used for grouped content that needs a boundary but not the full
/// `BrevCard` glass treatment. One canonical recipe keeps the ~15 call sites
/// from drifting on opacity values.
public struct BrevQuietSurface: ViewModifier {
    @Environment(\.brevTheme) private var theme

    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = BrevRadius.md) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(theme.bgSecondary.color.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
            }
    }
}

public extension View {
    /// Applies the shared quiet inset-surface recipe (faint secondary fill +
    /// hairline border). Prefer this over hand-rolled background/stroke pairs.
    func brevQuietSurface(cornerRadius: CGFloat = BrevRadius.md) -> some View {
        modifier(BrevQuietSurface(cornerRadius: cornerRadius))
    }
}
