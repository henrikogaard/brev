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

enum ComposeBodyAppearance: String, CaseIterable, Hashable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "compose.bodyAppearance.v2" // gitleaks:allow, UserDefaults key

    static func resolve(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .system
    }

    func resolved(for themeMode: BrevThemeMode) -> Self {
        switch self {
        case .system:
            return themeMode == .dark ? .dark : .light
        case .light, .dark:
            return self
        }
    }

    var label: String {
        switch self {
        case .system:
            return String(localized: "Match Theme", bundle: .module)
        case .light:
            return String(localized: "Light", bundle: .module)
        case .dark:
            return String(localized: "Dark", bundle: .module)
        }
    }

    var symbolName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .system:
            return .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var editorTheme: BrevTheme {
        switch self {
        case .system:
            return .brevMonoLight
        case .light:
            return .brevMonoLight
        case .dark:
            return .brevMonoDark
        }
    }
}
