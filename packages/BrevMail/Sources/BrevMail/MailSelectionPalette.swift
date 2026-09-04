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
struct MailSelectionPalette: Equatable {
    let background: BrevColor
    let text: BrevColor
    let detail: BrevColor
    let indicator: BrevColor

    init(theme: BrevTheme, isActive: Bool = true) {
        background = theme.selection
        text = theme.textPrimary
        detail = theme.textSecondary
        indicator = isActive ? theme.textPrimary : theme.textSecondary
    }
}
