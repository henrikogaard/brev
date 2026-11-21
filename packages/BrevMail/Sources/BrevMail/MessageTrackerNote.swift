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

/// The quiet tracker-count note above a message with remote content allowed (#299).
struct MessageTrackerNote: View {
    @Environment(\.brevTheme) private var theme

    let trackerCount: Int
    let strippingEnabled: Bool

    /// The note's text; nil when no likely trackers were found.
    static func text(trackerCount: Int, strippingEnabled: Bool = true) -> String? {
        // Singular and plural are separate keys: SwiftPM test builds on older
        // toolchains do not resolve catalog plural variations.
        guard trackerCount > 0 else { return nil }
        if strippingEnabled {
            if trackerCount == 1 {
                return String(localized: "Blocked 1 tracker", bundle: .module)
            }
            return String(localized: "Blocked \(trackerCount) trackers", bundle: .module)
        }
        if trackerCount == 1 {
            return String(localized: "1 likely tracker may load", bundle: .module)
        }
        return String(localized: "\(trackerCount) likely trackers may load", bundle: .module)
    }

    var body: some View {
        if let text = Self.text(trackerCount: trackerCount, strippingEnabled: strippingEnabled) {
            Label(text, systemImage: strippingEnabled ? "eye.slash" : "eye")
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityLabel(text)
        }
    }
}

enum MessageTrackingPixelPreference {
    static let storageKey = "body.stripTrackingPixels"
    static let enabledByDefault = true
}
