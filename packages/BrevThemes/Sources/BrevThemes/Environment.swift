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

private struct BrevThemeKey: EnvironmentKey {
    static let defaultValue: BrevTheme = .brevMonoLight
}

public extension EnvironmentValues {
    /// The active Brev theme. Inject via `.brevTheme(_:)` on a view
    /// (typically the root scene). All Brev views read this and pull
    /// colors from it — never from literals (ADR-0002, ADR-0005).
    var brevTheme: BrevTheme {
        get { self[BrevThemeKey.self] }
        set { self[BrevThemeKey.self] = newValue }
    }
}

public extension View {
    /// Inject a `BrevTheme` into the environment and pin the color
    /// scheme to match the theme's mode (so system widgets render in
    /// the same scheme as the themed app chrome).
    func brevTheme(_ theme: BrevTheme) -> some View {
        environment(\.brevTheme, theme)
            .preferredColorScheme(theme.mode.colorScheme)
    }
}
