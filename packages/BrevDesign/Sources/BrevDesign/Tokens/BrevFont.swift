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
#if os(macOS)
import AppKit
#endif

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
        font(design: .default)
    }

    /// The token in a specific font design (ADR-0086 section families).
    public func font(design: Font.Design) -> Font {
        switch self {
        case .largeTitle: return .system(.largeTitle, design: design).weight(.semibold)
        case .title: return .system(.title2, design: design).weight(.semibold)
        case .headline: return .system(.headline, design: design).weight(.semibold)
        case .body: return .system(.body, design: design)
        case .callout: return .system(.callout, design: design)
        case .subheadline: return .system(.subheadline, design: design).weight(.medium)
        case .footnote: return .system(.footnote, design: design)
        case .caption: return .system(.caption, design: design)
        }
    }
}

public extension View {
    /// Apply a Brev typography token.
    func brevFont(_ token: BrevFont) -> some View {
        modifier(BrevFontModifier(token: token))
    }
}

private struct BrevFontModifier: ViewModifier {
    let token: BrevFont
    @AppStorage(MailboxViewPreferenceKey.textSize) private var textSizeRaw = MailboxTextSize.medium.rawValue
    @Environment(\.brevFontFamily) private var family

    func body(content: Content) -> some View {
        #if os(macOS)
        let textSize = MailboxTextSize(rawValue: textSizeRaw) ?? .medium
        content.font(token.desktopFont(textSize: textSize, design: family.fontDesign))
        #else
        content.font(token.font(design: family.fontDesign))
        #endif
    }
}

#if os(macOS)
extension BrevFont {
    func desktopFont(textSize: MailboxTextSize, design: Font.Design = .default) -> Font {
        // Non-default designs take the explicit-size path: on macOS a text-style
        // font did not visibly pick up `.rounded` in testing.
        guard textSize != .medium || design != .default else { return font }
        let style: NSFont.TextStyle = switch self {
        case .largeTitle: .largeTitle
        case .title: .title2
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        }
        let weight: Font.Weight = switch self {
        case .largeTitle, .title, .headline: .semibold
        case .subheadline: .medium
        default: .regular
        }
        let adjustment: CGFloat = switch textSize {
        case .small: -1
        case .medium: 0
        case .large: 2
        }
        return .system(
            size: NSFont.preferredFont(forTextStyle: style).pointSize + adjustment,
            weight: weight,
            design: design
        )
    }
}
#endif

public extension View {
    /// Applies the saved desktop text size and density to inherited labels and controls.
    /// System-owned menu bars and dialogs retain their native sizing.
    func brevDesktopSizing() -> some View {
        modifier(BrevDesktopSizingModifier())
    }
}

private struct BrevDesktopSizingModifier: ViewModifier {
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var densityRaw = MailboxListDensity.platformDefault.rawValue

    func body(content: Content) -> some View {
        #if os(macOS)
        let density = MailboxListDensity(rawValue: densityRaw) ?? .comfortable
        content.brevFont(.body)
            .controlSize(density == .compact ? .small : density == .spacious ? .large : .regular)
        #else
        content
        #endif
    }
}
