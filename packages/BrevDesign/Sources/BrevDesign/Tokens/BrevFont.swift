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
        modifier(BrevFontModifier(token: token))
    }
}

private struct BrevFontModifier: ViewModifier {
    let token: BrevFont
    @AppStorage(MailboxViewPreferenceKey.textSize) private var textSizeRaw = MailboxTextSize.medium.rawValue

    func body(content: Content) -> some View {
        #if os(macOS)
        let textSize = MailboxTextSize(rawValue: textSizeRaw) ?? .medium
        content.font(token.desktopFont(textSize: textSize))
        #else
        content.font(token.font)
        #endif
    }
}

#if os(macOS)
extension BrevFont {
    func desktopFont(textSize: MailboxTextSize) -> Font {
        guard textSize != .medium else { return font }
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
        let adjustment: CGFloat = textSize == .small ? -1 : 2
        return .system(size: NSFont.preferredFont(forTextStyle: style).pointSize + adjustment, weight: weight)
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
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var densityRaw = MailboxListDensity.comfortable.rawValue

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
