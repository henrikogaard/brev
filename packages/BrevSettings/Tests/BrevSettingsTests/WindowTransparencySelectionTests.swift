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
@testable import BrevSettings
import Testing

@Suite("Window transparency choices")
struct WindowTransparencySelectionTests {
    @Test("coverage choices preserve opacity and material while selecting the correct windows")
    func selectionPreservesTuning() {
        var preferences = WindowAppearancePreferences(mode: .frosted, scope: .mainWindow,
                                                      surfaceOpacity: 0.74, sidebarOpacity: 0.42)
        #expect(WindowTransparencySelection(preferences) == .fullWindows)
        WindowTransparencySelection.sidebars.apply(to: &preferences)
        #expect(preferences.scope == .sidebarOnly)
        #expect(preferences.mode == .frosted)
        #expect(preferences.surfaceOpacity == 0.74)
        #expect(preferences.sidebarOpacity == 0.42)
        WindowTransparencySelection.fullWindows.apply(to: &preferences)
        #expect(preferences.scope == .allWindows)
        #expect(preferences.usesTransparentWindowChrome(for: .utility, reduceTransparency: false))
        WindowTransparencySelection.off.apply(to: &preferences)
        #expect(preferences.mode == .solid)
        #expect(preferences.surfaceFillOpacity(for: .sidebar, reduceTransparency: false) == 1)
    }

    @Test("enabling sidebars from solid keeps Settings content and compose opaque")
    func enablingSidebarsFromOff() {
        var preferences = WindowAppearancePreferences.defaults
        #expect(WindowTransparencySelection(preferences) == .off)
        WindowTransparencySelection.sidebars.apply(to: &preferences)
        #expect(preferences.mode == .subtle)
        #expect(preferences.scope == .sidebarOnly)
        #expect(preferences.surfaceFillOpacity(for: .sidebar, reduceTransparency: false) == 0.59)
        #expect(preferences.surfaceFillOpacity(for: .content, reduceTransparency: false) == 1)
        #expect(preferences.surfaceFillOpacity(for: .utility, reduceTransparency: false) == 1)
        #expect(preferences.surfaceFillOpacity(for: .sidebar, reduceTransparency: true) == 1)
    }
}
