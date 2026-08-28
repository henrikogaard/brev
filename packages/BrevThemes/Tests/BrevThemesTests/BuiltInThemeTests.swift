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

@testable import BrevThemes
import Testing

@Suite("Built-in themes")
struct BuiltInThemeTests {
    @Test("built-in theme IDs stay unique")
    func builtInThemeIDsStayUnique() {
        let ids = BrevTheme.brevBuiltIns.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test("developer packs are included in display order")
    func developerPacksAreIncludedInDisplayOrder() {
        let developerPackIDs = BrevTheme.brevBuiltIns.suffix(21).map(\.id)

        #expect(developerPackIDs == [
            "forge-light",
            "forge-dark",
            "one-dark-pro",
            "command-dark",
            "blurple-night",
            "midnight-terminal",
            "cobalt-night",
            "code-candy-dark",
            "pearl-light",
            "evergreen-night",
            "ink-wave",
            "mirage-ember",
            "oceanic-dark",
            "amber-terminal",
            "owl-blue",
            "synthwave-dusk",
            "zenwritten-light",
            "zenwritten-dark",
            "tender",
            "tomorrow-day",
            "tomorrow-night"
        ])
    }

    @Test("Nordic is grouped next to Nord")
    func nordicIsGroupedNextToNord() {
        let ids = BrevTheme.brevBuiltIns.map(\.id)

        #expect(ids.firstIndex(of: "nordic") == ids.firstIndex(of: "nord").map { $0 + 1 })
    }

    @Test("built-in themes cover light and dark choices")
    func builtInThemesCoverLightAndDarkChoices() {
        #expect(BrevTheme.brevBuiltIns.count == 36)
        #expect(BrevTheme.brevBuiltIns.filter { $0.mode == .light }.count == 10)
        #expect(BrevTheme.brevBuiltIns.filter { $0.mode == .dark }.count == 26)
    }

    @Test("built-in themes define complete avatar palettes")
    func builtInThemesDefineCompleteAvatarPalettes() {
        for theme in BrevTheme.brevBuiltIns {
            #expect(theme.avatarPalette.count == 8, "\(theme.id) should expose eight avatar colors")
        }
    }

    @Test("accent overrides preserve the rest of the theme")
    func accentOverridePreservesTheRestOfTheTheme() {
        let theme = BrevTheme.brevSlate
        let overridden = theme.withAccent(BrevColor("#E85D75"))

        #expect(overridden.accent.hex == "#E85D75")
        #expect(overridden.id == theme.id)
        #expect(overridden.bgPrimary == theme.bgPrimary)
        #expect(overridden.selection == theme.selection)
        #expect(overridden.avatarPalette == theme.avatarPalette)
    }

    @Test("default theme pair uses monochrome chrome and semantic state colors")
    func defaultThemePairUsesMonochromeChrome() {
        #expect(BrevTheme.brevMonoLight.bgPrimary.hex == "#FFFFFF")
        #expect(BrevTheme.brevMonoLight.accent.hex == "#1F1F1F")
        #expect(BrevTheme.brevMonoLight.success.hex == "#3B6B4C")
        #expect(BrevTheme.brevMonoDark.bgPrimary.hex == "#101010")
        #expect(BrevTheme.brevMonoDark.accent.hex == "#E6E6E6")
    }
}
