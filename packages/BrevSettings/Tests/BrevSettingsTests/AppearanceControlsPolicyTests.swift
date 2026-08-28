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

@testable import BrevSettings
import Testing

@Suite("AppearanceControlsPolicy")
struct AppearanceControlsPolicyTests {
    @Test("macOS shows window translucency and transparent-titlebar controls")
    func macOSShowsWindowChrome() {
        let policy = AppearanceControlsPolicy.forPlatform(.macOS)
        #expect(policy.showsWindowTranslucencyControls)
        #expect(policy.showsTransparentTitleBarToggle)
    }

    @Test("iOS hides window-chrome controls that have no effect")
    func iOSHidesWindowChrome() {
        let policy = AppearanceControlsPolicy.forPlatform(.iOS)
        #expect(!policy.showsWindowTranslucencyControls)
        #expect(!policy.showsTransparentTitleBarToggle)
    }

    @Test("theme and app-icon controls show on both platforms")
    func sharedControlsAlwaysShow() {
        for platform in [AppearanceControlsPolicy.Platform.macOS, .iOS] {
            let policy = AppearanceControlsPolicy.forPlatform(platform)
            #expect(policy.showsThemePicker)
            #expect(policy.showsAppIconPicker)
        }
    }
}
