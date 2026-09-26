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
import SwiftUI

/// The neutral rounded selection fill shared by the PIM lists
/// (calendar agenda, contacts, tasks) so they match the mail list's
/// selection instead of the system accent List highlight.
struct PIMSelectionRowBackground: View {
    @Environment(\.brevTheme) private var theme
    let isSelected: Bool

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                .fill(BrevSelectionPalette(theme: theme).background.color)
                .padding(.horizontal, BrevSpacing.xxs)
        } else {
            Color.clear
        }
    }
}
