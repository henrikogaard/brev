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
import SwiftUI

/// Light / dark intent declared by a theme. Mirrors `ColorScheme` but
/// is `Codable` so it survives JSON theme files.
public enum BrevThemeMode: String, Codable, Sendable, Hashable {
    case light
    case dark

    public var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A complete theme: fifteen semantic tokens plus an avatar palette.
///
/// See ADR-0002 §Theme definition. The token set is deliberately
/// fixed; new UI roles get new tokens via a follow-up ADR rather than
/// per-view colors.
public struct BrevTheme: Identifiable, Codable, Sendable, Hashable {
    // Metadata
    public let id: String
    public let name: String
    public let mode: BrevThemeMode
    public let author: String
    public let license: String

    // Surfaces
    public let bgPrimary: BrevColor
    public let bgSecondary: BrevColor
    public let bgTertiary: BrevColor

    // Text
    public let textPrimary: BrevColor
    public let textSecondary: BrevColor
    public let textTertiary: BrevColor

    // Accents
    public let accent: BrevColor
    public let accentMuted: BrevColor
    public let success: BrevColor
    public let warning: BrevColor
    public let danger: BrevColor
    public let info: BrevColor

    // Structure
    public let border: BrevColor
    public let separator: BrevColor
    public let selection: BrevColor

    // Avatar fallback palette (ADR-0003)
    public let avatarPalette: [BrevColor]

    public init(
        id: String,
        name: String,
        mode: BrevThemeMode,
        author: String,
        license: String,
        bgPrimary: BrevColor,
        bgSecondary: BrevColor,
        bgTertiary: BrevColor,
        textPrimary: BrevColor,
        textSecondary: BrevColor,
        textTertiary: BrevColor,
        accent: BrevColor,
        accentMuted: BrevColor,
        success: BrevColor,
        warning: BrevColor,
        danger: BrevColor,
        info: BrevColor,
        border: BrevColor,
        separator: BrevColor,
        selection: BrevColor,
        avatarPalette: [BrevColor]
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.author = author
        self.license = license
        self.bgPrimary = bgPrimary
        self.bgSecondary = bgSecondary
        self.bgTertiary = bgTertiary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.accentMuted = accentMuted
        self.success = success
        self.warning = warning
        self.danger = danger
        self.info = info
        self.border = border
        self.separator = separator
        self.selection = selection
        self.avatarPalette = avatarPalette
    }

    /// Returns this theme with its semantic accent token replaced.
    ///
    /// All other palette roles remain unchanged so a user accent override
    /// does not silently alter surfaces, status colors, or avatar fallbacks.
    public func withAccent(_ accent: BrevColor) -> BrevTheme {
        BrevTheme(
            id: id,
            name: name,
            mode: mode,
            author: author,
            license: license,
            bgPrimary: bgPrimary,
            bgSecondary: bgSecondary,
            bgTertiary: bgTertiary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accent,
            accentMuted: accentMuted,
            success: success,
            warning: warning,
            danger: danger,
            info: info,
            border: border,
            separator: separator,
            selection: selection,
            avatarPalette: avatarPalette
        )
    }
}
