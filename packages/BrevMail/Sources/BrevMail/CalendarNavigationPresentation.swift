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

import Foundation

/// Labels and sizes for the Calendar's previous/next controls (audit
/// finding P2). The glyph stays a bare chevron; the label says what a step
/// moves by in the active layout.
enum CalendarNavigationPresentation {
    /// Smallest touch target for a chevron or toolbar glyph, in points.
    static let minimumControlSize: CGFloat = 44

    /// "Previous Week" for the week layout; "Previous" where no step applies.
    static func previousLabel(for mode: CalendarBrowsingModel.ViewMode) -> String {
        switch mode {
        case .agenda:
            String(localized: "Previous", bundle: .module)
        case .day:
            String(localized: "Previous Day", bundle: .module)
        case .week:
            String(localized: "Previous Week", bundle: .module)
        case .month:
            String(localized: "Previous Month", bundle: .module)
        }
    }

    /// "Next Week" for the week layout; "Next" where no step applies.
    static func nextLabel(for mode: CalendarBrowsingModel.ViewMode) -> String {
        switch mode {
        case .agenda:
            String(localized: "Next", bundle: .module)
        case .day:
            String(localized: "Next Day", bundle: .module)
        case .week:
            String(localized: "Next Week", bundle: .module)
        case .month:
            String(localized: "Next Month", bundle: .module)
        }
    }
}
