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

import BrevSettings
import BrevThemes
import Foundation

public enum ThemePreferences {
    public static let themeIDKey = "appearance.themeID"

    public static func load(
        defaults: UserDefaults = .standard,
        builtIns: [BrevTheme] = BrevTheme.brevBuiltIns
    ) -> BrevTheme {
        guard let id = defaults.string(forKey: themeIDKey),
              let theme = builtIns.first(where: { $0.id == id })
        else {
            return .brevMonoLight
        }
        return theme
    }

    public static func hasSavedTheme(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: themeIDKey) != nil
    }

    /// Resolves the theme for the first rendered frame, before asynchronous app
    /// bootstrap can copy the active system appearance into `AppSession`.
    public static func resolvedForLaunch(
        prefersDark: Bool,
        defaults: UserDefaults = .standard,
        builtIns: [BrevTheme] = BrevTheme.brevBuiltIns
    ) -> BrevTheme {
        if !AppearanceThemeSettings.hasSavedValue(in: defaults),
           hasSavedTheme(defaults: defaults) {
            return load(defaults: defaults, builtIns: builtIns)
        }

        return AppearanceThemeSettings.load(from: defaults).resolvedTheme(
            in: builtIns,
            prefersDark: prefersDark
        )
    }

    /// Whether the root scene should leave its preferred color scheme unset so
    /// SwiftUI can observe and follow the operating system appearance.
    public static func followsSystemAppearance(defaults: UserDefaults = .standard) -> Bool {
        if AppearanceThemeSettings.hasSavedValue(in: defaults) {
            return AppearanceThemeSettings.load(from: defaults).followsSystemAppearance
        }
        return !hasSavedTheme(defaults: defaults)
    }

    public static func save(_ theme: BrevTheme, defaults: UserDefaults = .standard) {
        defaults.set(theme.id, forKey: themeIDKey)
    }
}
