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

/// The quiet "Blocked 2 trackers" note above a message whose remote content
/// is allowed but whose tracking pixels were removed (#299).
struct MessageTrackerNote: View {
    @Environment(\.brevTheme) private var theme

    let removedCount: Int

    /// The note's text; nil when nothing was removed.
    static func text(removedCount: Int) -> String? {
        // Singular and plural are separate keys: SwiftPM test builds on older
        // toolchains do not resolve catalog plural variations.
        switch removedCount {
        case ..<1: nil
        case 1: String(localized: "Blocked 1 tracker", bundle: .module)
        default: String(localized: "Blocked \(removedCount) trackers", bundle: .module)
        }
    }

    var body: some View {
        if let text = Self.text(removedCount: removedCount) {
            Label(text, systemImage: "eye.slash")
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityLabel(text)
        }
    }
}
