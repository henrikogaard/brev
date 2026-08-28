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

import SwiftUI

/// Semantic typography ramp for Brev.
///
/// Lives in BrevDesign so the per-view code never reaches for
/// `.system(size:weight:)` literals (which would scatter the type
/// scale across the codebase). Every view consumes a `BrevFont`.
public enum BrevFont: Sendable, Hashable, CaseIterable {
    /// Window titles and view headlines.
    case largeTitle
    /// Folder / section titles.
    case title
    /// Toolbar buttons and prominent labels.
    case headline
    /// Default body text — message previews, settings rows.
    case body
    /// Secondary body — snippets, secondary labels.
    case callout
    /// Sender / subject in the message list.
    case subheadline
    /// Footnotes, timestamps.
    case footnote
    /// Tiny caption text — badges, counters.
    case caption

    /// Resolves to a SwiftUI `Font`. Uses Apple's Dynamic Type ramp so
    /// accessibility scaling works out of the box.
    public var font: Font {
        switch self {
        case .largeTitle: return .system(.largeTitle, design: .default).weight(.semibold)
        case .title: return .system(.title2, design: .default).weight(.semibold)
        case .headline: return .system(.headline, design: .default).weight(.semibold)
        case .body: return .system(.body, design: .default)
        case .callout: return .system(.callout, design: .default)
        case .subheadline: return .system(.subheadline, design: .default).weight(.medium)
        case .footnote: return .system(.footnote, design: .default)
        case .caption: return .system(.caption, design: .default)
        }
    }
}

public extension View {
    /// Apply a Brev typography token.
    func brevFont(_ token: BrevFont) -> some View {
        font(token.font)
    }
}
