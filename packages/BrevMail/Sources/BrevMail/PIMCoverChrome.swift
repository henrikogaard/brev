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

/// The navigation-bar Done button the Calendar, Contacts and Tasks covers
/// share on iOS (audit findings P1 and P2).
///
/// It sits at the trailing end like the Settings sheet's Done, and uses the
/// primary text colour so it passes contrast on every theme; the tint
/// accent did not.
struct PIMDoneButton: View {
    @Environment(\.brevTheme) private var theme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Done", bundle: .module)
                .foregroundStyle(theme.textPrimary.color)
        }
    }
}

/// Adds the search field only while it has something to search.
///
/// A cover with no connected source has nothing to filter, so the field is
/// hidden there (audit finding P1). The condition is constant on macOS.
struct PIMSearchableModifier: ViewModifier {
    @Binding var text: String
    let prompt: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

extension View {
    /// Themes an editor sheet presented from a PIM cover the way every other
    /// iOS sheet is themed. macOS editors keep their current presentation.
    @ViewBuilder
    func pimEditorSheetAppearance(_ theme: BrevTheme) -> some View {
        #if os(iOS)
        brevSheetAppearance(theme)
        #else
        self
        #endif
    }
}
