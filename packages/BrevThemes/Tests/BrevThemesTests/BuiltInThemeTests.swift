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
import Foundation
import Testing

@Suite("Built-in themes")
struct BuiltInThemeTests {
    @Test("default themes keep small text readable across normal, hover, and selected surfaces",
          arguments: [BrevTheme.brevMonoLight, BrevTheme.brevMonoGrey, BrevTheme.brevMonoDark])
    func defaultContrast(theme: BrevTheme) {
        for background in [theme.bgPrimary, theme.bgSecondary, theme.bgTertiary, theme.selection] {
            for foreground in [theme.textPrimary, theme.textSecondary, theme.textTertiary] {
                #expect(Self.contrast(foreground, background) >= 4.5,
                        "\(theme.id): \(foreground.hex) on \(background.hex)")
            }
        }
        #expect(Self.contrast(theme.textPrimary, theme.selection) >= 3)
        #expect(Self.contrast(theme.textSecondary, theme.selection) >= 3)
    }

    @Test("built-in metadata text stays readable on primary and secondary surfaces")
    func builtInMetadataContrast() {
        for theme in BrevTheme.brevBuiltIns {
            for background in [theme.bgPrimary, theme.bgSecondary] {
                for foreground in [theme.textSecondary, theme.textTertiary] {
                    #expect(Self.contrast(foreground, background) >= 4.5,
                            "\(theme.id): \(foreground.hex) on \(background.hex)")
                }
            }
        }
    }

    @Test("built-in accent, warning and danger stay readable as text on primary and secondary surfaces",
          arguments: BrevTheme.brevBuiltIns)
    func builtInStatusTextContrast(theme: BrevTheme) {
        for background in [theme.bgPrimary, theme.bgSecondary] {
            for (role, foreground) in [
                ("accent", theme.accent),
                ("warning", theme.warning),
                ("danger", theme.danger)
            ] {
                #expect(foreground.contrastRatio(against: background) >= 4.5,
                        "\(theme.id) \(role): \(foreground.hex) on \(background.hex)")
            }
        }
    }

    @Test("built-in success and info glyph colors meet the 3:1 non-text contrast",
          arguments: BrevTheme.brevBuiltIns)
    func builtInStatusGlyphContrast(theme: BrevTheme) {
        for background in [theme.bgPrimary, theme.bgSecondary] {
            for (role, foreground) in [("success", theme.success), ("info", theme.info)] {
                #expect(foreground.contrastRatio(against: background) >= 3,
                        "\(theme.id) \(role): \(foreground.hex) on \(background.hex)")
            }
        }
    }

    @Test("control borders meet the 3:1 non-text contrast on every built-in theme",
          arguments: BrevTheme.brevBuiltIns)
    func builtInControlBorderContrast(theme: BrevTheme) {
        for background in [theme.bgPrimary, theme.bgSecondary] {
            #expect(theme.controlBorder.contrastRatio(against: background) >= 3,
                    "\(theme.id): \(theme.controlBorder.hex) on \(background.hex)")
        }
    }

    @Test("control border only strengthens a border that is below 3:1",
          arguments: BrevTheme.brevBuiltIns)
    func controlBorderOnlyStrengthensWhenNeeded(theme: BrevTheme) {
        let borderPasses = [theme.bgPrimary, theme.bgSecondary]
            .allSatisfy { theme.border.contrastRatio(against: $0) >= 3 }
        if borderPasses {
            #expect(theme.controlBorder == theme.border, "\(theme.id)")
        } else {
            #expect(theme.controlBorder != theme.border, "\(theme.id)")
        }
    }

    @Test("accent text on its own tint reaches 4.5:1 on every built-in theme",
          arguments: BrevTheme.brevBuiltIns)
    func accentTextOnTintContrast(theme: BrevTheme) {
        let opacity = 0.18
        let text = theme.accentTextOnTint(opacity: opacity)
        for surface in [theme.bgPrimary, theme.bgSecondary] {
            let tinted = surface.blended(with: theme.accent, amount: opacity)
            #expect(text.contrastRatio(against: tinted) >= 4.5,
                    "\(theme.id): \(text.hex) on \(tinted.hex)")
        }
    }

    @Test("accent text on tint keeps the accent when it is already readable")
    func accentTextOnTintKeepsReadableAccent() {
        let theme = BrevTheme.brevMonoLight
        #expect(theme.accentTextOnTint(opacity: 0.18) == theme.accent)
    }

    private static func contrast(_ first: BrevColor, _ second: BrevColor) -> Double {
        func luminance(_ color: BrevColor) -> Double {
            let rgb = UInt32(color.hex.dropFirst(), radix: 16)!
            func linearChannel(_ value: UInt32) -> Double {
                let normalized = Double(value) / 255.0
                if normalized <= 0.04045 {
                    return normalized / 12.92
                }
                return pow((normalized + 0.055) / 1.055, 2.4)
            }
            let red = linearChannel((rgb >> 16) & 255)
            let green = linearChannel((rgb >> 8) & 255)
            let blue = linearChannel(rgb & 255)
            return red * 0.2126 + green * 0.7152 + blue * 0.0722
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

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
        #expect(BrevTheme.brevBuiltIns.count == 37)
        #expect(BrevTheme.brevBuiltIns.filter { $0.mode == .light }.count == 10)
        #expect(BrevTheme.brevBuiltIns.filter { $0.mode == .dark }.count == 27)
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

    @Test("BrevColor reports WCAG contrast for sRGB colors")
    func colorContrastRatio() {
        #expect(BrevColor("#000000").contrastRatio(against: BrevColor("#FFFFFF")) >= 20.99)
        #expect(BrevColor("#777777").contrastRatio(against: BrevColor("#FFFFFF")) >= 4.47)
    }

    @Test("readable accents adjust black and white for light and dark surfaces")
    func readableAccentsMeetNormalContrast() {
        for theme in [BrevTheme.brevMonoLight, BrevTheme.brevMonoGrey] {
            for accent in [BrevColor("#000000"), BrevColor("#FFFFFF")] {
                let readable = theme.withAccent(accent).withReadableAccent()
                for surface in [theme.bgPrimary, theme.bgSecondary, theme.bgTertiary] {
                    #expect(
                        readable.accent.contrastRatio(against: surface) >= 4.5,
                        "\(theme.id): \(readable.accent.hex) on \(surface.hex)"
                    )
                }
            }
        }
    }

    @Test("increased contrast prefers the seven to one target")
    func readableAccentsMeetIncreasedContrastWhenFeasible() {
        for theme in [BrevTheme.brevMonoLight, BrevTheme.brevMonoGrey] {
            let readable = theme
                .withAccent(BrevColor("#808080"))
                .withReadableAccent(increasedContrast: true)

            for surface in [theme.bgPrimary, theme.bgSecondary, theme.bgTertiary] {
                #expect(readable.accent.contrastRatio(against: surface) >= 7)
            }
        }
    }

    @Test("readable accent transformation preserves non-accent palette roles")
    func readableAccentPreservesPalette() {
        let theme = BrevTheme.brevSlate
        let readable = theme.withAccent(BrevColor("#808080")).withReadableAccent()

        #expect(readable.bgPrimary == theme.bgPrimary)
        #expect(readable.selection == theme.selection)
        #expect(readable.success == theme.success)
        #expect(readable.avatarPalette == theme.avatarPalette)
    }

    @Test("default theme pair uses monochrome chrome and semantic state colors")
    func defaultThemePairUsesMonochromeChrome() {
        #expect(BrevTheme.brevMonoLight.bgPrimary.hex == "#FFFFFF")
        #expect(BrevTheme.brevMonoLight.accent.hex == "#1F1F1F")
        #expect(BrevTheme.brevMonoLight.success.hex == "#3B6B4C")
        #expect(BrevTheme.brevMonoGrey.bgPrimary.hex == "#292929")
        #expect(BrevTheme.brevMonoGrey.accent.hex == "#E6E6E6")
    }
}
