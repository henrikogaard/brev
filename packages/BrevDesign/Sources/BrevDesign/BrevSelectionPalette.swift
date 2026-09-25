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

/// Shared opaque selection roles; accent overrides never change text contrast.
public struct BrevSelectionPalette: Equatable {
    public let background: BrevColor
    public let text: BrevColor
    public let detail: BrevColor
    public let indicator: BrevColor

    /// Resolves selection colors while keeping accent preferences independent.
    /// `isActive: false` (window inactive, or the pane does not hold keyboard
    /// focus) demotes the fill to `bgSecondary`, the Apple Mail
    /// focused-pane-owns-the-selection cue — no focus ring is drawn.
    public init(theme: BrevTheme, isActive: Bool = true) {
        background = isActive ? theme.selection : theme.bgSecondary
        text = theme.textPrimary
        detail = theme.textSecondary
        indicator = isActive ? theme.textPrimary : theme.textSecondary
    }
}
