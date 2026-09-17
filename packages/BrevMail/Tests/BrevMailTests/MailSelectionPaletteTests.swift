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

@testable import BrevMail
import BrevThemes
import Testing

struct MailSelectionPaletteTests {
    @Test("accent overrides and inactive windows preserve readable selected text",
          arguments: [BrevTheme.brevMonoLight, BrevTheme.brevMonoDark])
    func selectedRoles(theme: BrevTheme) {
        let active = MailSelectionPalette(theme: theme)
        let inactive = MailSelectionPalette(theme: theme, isActive: false)
        let overridden = MailSelectionPalette(theme: theme.withAccent(BrevColor("#FFFF00")))
        #expect(active.background == theme.selection)
        #expect(active.text == theme.textPrimary)
        #expect(active.detail == theme.textSecondary)
        #expect(inactive.background == active.background)
        #expect(inactive.text == active.text)
        #expect(inactive.indicator == theme.textSecondary)
        #expect(overridden == active)
    }
}
