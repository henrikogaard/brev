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

@testable import BrevDesign
#if os(macOS)
import AppKit
#endif
import Foundation
import Testing

@Suite("WindowAppearancePreferences")
struct WindowAppearancePreferencesTests {
    @Test("defaults keep windows solid and scope material to the main window")
    func defaultsKeepWindowsSolid() throws {
        let defaults = try Self.makeDefaults()

        let preferences = WindowAppearancePreferences.load(from: defaults)

        #expect(preferences.mode == .solid)
        #expect(preferences.scope == .mainWindow)
        #expect(preferences.surfaceOpacity == 0.82)
        #expect(preferences.sidebarOpacity == 0.59)
        #expect(preferences.messageContentOpacityMode == .followPane)
        #expect(preferences.messageContentOpacity == 0.82)
        #expect(preferences.effectiveMode(reduceTransparency: false) == .solid)
        #expect(preferences.usesMaterial(for: .mainWindow, reduceTransparency: false) == false)
    }

    @Test("saving and loading preserves the selected mode, scope, and opacity values")
    func savingAndLoadingPreservesSelectedModeAndScope() throws {
        let defaults = try Self.makeDefaults()
        let preferences = WindowAppearancePreferences(
            mode: .frosted,
            scope: .allWindows,
            surfaceOpacity: 0.9,
            sidebarOpacity: 0.34,
            messageContentOpacityMode: .custom,
            messageContentOpacity: 0.76
        )

        preferences.save(to: defaults)
        let restored = WindowAppearancePreferences.load(from: defaults)

        #expect(restored == preferences)
        #expect(defaults.string(forKey: WindowAppearancePreferenceKey.mode) == "frosted")
        #expect(defaults.string(forKey: WindowAppearancePreferenceKey.scope) == "allWindows")
        #expect(defaults.double(forKey: WindowAppearancePreferenceKey.surfaceOpacity) == 0.9)
        #expect(defaults.double(forKey: WindowAppearancePreferenceKey.sidebarOpacity) == 0.34)
        #expect(defaults.string(forKey: WindowAppearancePreferenceKey.messageContentOpacityMode) == "custom")
        #expect(defaults.double(forKey: WindowAppearancePreferenceKey.messageContentOpacity) == 0.76)
    }

    @Test("sidebar scope only applies material to sidebar surfaces")
    func sidebarScopeOnlyAppliesMaterialToSidebarSurfaces() {
        let preferences = WindowAppearancePreferences(
            mode: .subtle,
            scope: .sidebarOnly
        )

        #expect(preferences.usesMaterial(for: .sidebar, reduceTransparency: false) == true)
        #expect(preferences.usesMaterial(for: .content, reduceTransparency: false) == false)
        #expect(preferences.usesMaterial(for: .settings, reduceTransparency: false) == false)
        #expect(preferences.usesTransparentWindowChrome(for: .mainWindow, reduceTransparency: false) == true)
        #expect(preferences.usesTransparentWindowChrome(for: .settings, reduceTransparency: false) == false)
    }

    @Test("window chrome follows the selected scope")
    func windowChromeFollowsSelectedScope() {
        let mainWindowOnly = WindowAppearancePreferences(
            mode: .frosted,
            scope: .mainWindow
        )
        let allWindows = WindowAppearancePreferences(
            mode: .frosted,
            scope: .allWindows
        )

        #expect(mainWindowOnly.usesTransparentWindowChrome(for: .mainWindow, reduceTransparency: false) == true)
        // Settings follows Main window scope so Appearance → Window design is
        // visible in the Settings window without requiring All windows.
        #expect(mainWindowOnly.usesTransparentWindowChrome(for: .settings, reduceTransparency: false) == true)
        #expect(mainWindowOnly.usesTransparentWindowChrome(for: .utility, reduceTransparency: false) == false)
        #expect(allWindows.usesTransparentWindowChrome(for: .settings, reduceTransparency: false) == true)
        #expect(allWindows.usesTransparentWindowChrome(for: .utility, reduceTransparency: false) == true)
    }

    @Test("Settings window material does not stack the pane opacity layer")
    func settingsWindowMaterialDoesNotStackPaneOpacity() {
        let preferences = WindowAppearancePreferences(
            mode: .frosted,
            scope: .mainWindow,
            surfaceOpacity: 0.82,
            sidebarOpacity: 0.41
        )

        #expect(preferences.usesMaterial(for: .settings, reduceTransparency: false) == true)
        #expect(preferences.usesSurfaceOpacity(for: .settings, reduceTransparency: false) == false)
        #expect(preferences.surfaceFillOpacity(for: .settings, reduceTransparency: false) == nil)
        #expect(preferences.surfaceFillOpacity(for: .content, reduceTransparency: false) == 0.82)
        #expect(preferences.usesMaterial(for: .settings, reduceTransparency: true) == false)
    }

    @Test("main and settings window transparent chrome follows the title bar preference toggle")
    func mainAndSettingsWindowTransparentChromeFollowTitlebarPreferenceToggle() {
        let preferences = WindowAppearancePreferences(
            mode: .frosted,
            scope: .mainWindow
        )

        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: .mainWindow,
            reduceTransparency: false,
            transparentMainTitlebar: true
        ) == true)

        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: .mainWindow,
            reduceTransparency: false,
            transparentMainTitlebar: false
        ) == false)

        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: .settings,
            reduceTransparency: false,
            transparentMainTitlebar: true
        ) == true)

        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: .settings,
            reduceTransparency: false,
            transparentMainTitlebar: false
        ) == false)
    }

    @Test("utility windows keep scoped transparent chrome regardless of title bar toggle")
    func utilityWindowsKeepScopedTransparentChromeRegardlessOfTitlebarToggle() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows
        )

        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: .utility,
            reduceTransparency: false,
            transparentMainTitlebar: false
        ) == true)
    }

    @Test("solid keeps main and settings backdrops opaque when unified title bars are enabled")
    func solidKeepsMainAndSettingsBackdropsOpaqueWithUnifiedTitlebars() {
        let preferences = WindowAppearancePreferences(
            mode: .solid,
            scope: .mainWindow
        )

        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: .mainWindow,
            reduceTransparency: false,
            transparentMainTitlebar: true
        ) == false)

        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: .settings,
            reduceTransparency: false,
            transparentMainTitlebar: true
        ) == false)
    }

    @Test("solid keeps subtle titlebar geometry without backdrop transparency")
    func solidKeepsSubtleTitlebarGeometryWithoutBackdropTransparency() {
        let solidPreferences = WindowAppearancePreferences(
            mode: .solid,
            scope: .mainWindow
        )
        let subtlePreferences = WindowAppearancePreferences(
            mode: .subtle,
            scope: .mainWindow
        )

        #expect(WindowTitlebarLayoutPolicy.usesUnifiedTitlebar(
            for: .mainWindow,
            unifiedTitlebarEnabled: true
        ))
        #expect(WindowTitlebarLayoutPolicy.usesUnifiedTitlebar(
            for: .settings,
            unifiedTitlebarEnabled: true
        ))
        #expect(!WindowTitlebarLayoutPolicy.usesUnifiedTitlebar(
            for: .mainWindow,
            unifiedTitlebarEnabled: false
        ))
        #expect(!WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: solidPreferences,
            for: .mainWindow,
            reduceTransparency: false,
            transparentMainTitlebar: true
        ))
        #expect(WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: subtlePreferences,
            for: .mainWindow,
            reduceTransparency: false,
            transparentMainTitlebar: true
        ))
    }

    @Test("settings windows follow all-window transparent chrome")
    func settingsWindowsFollowAllWindowTransparentChrome() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows
        )

        #expect(preferences.usesTransparentWindowChrome(for: .settings, reduceTransparency: false) == true)
        #expect(preferences.windowBackgroundAlpha(for: .settings, reduceTransparency: false) == 0)
    }

    @Test("compose utility windows can use transparent chrome")
    func composeUtilityWindowsCanUseTransparentChrome() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows
        )

        #expect(preferences.usesTransparentWindowChrome(for: .utility, reduceTransparency: false) == true)
        #expect(preferences.windowBackgroundAlpha(for: .utility, reduceTransparency: false) == 0)
    }

    #if os(macOS)
    @Test("secondary windows request standard resizable traffic-light controls")
    func secondaryWindowsRequestStandardResizableTrafficLightControls() {
        let settingsInsertions = WindowTrafficLightPolicy.styleMaskInsertions(for: .settings)
        let utilityInsertions = WindowTrafficLightPolicy.styleMaskInsertions(for: .utility)
        let contentInsertions = WindowTrafficLightPolicy.styleMaskInsertions(for: .content)

        #expect(settingsInsertions.contains(.miniaturizable))
        #expect(settingsInsertions.contains(.resizable))
        #expect(utilityInsertions.contains(.miniaturizable))
        #expect(utilityInsertions.contains(.resizable))
        #expect(contentInsertions.isEmpty)
    }

    @MainActor
    @Test("secondary traffic-light policy clears fixed content max size")
    func secondaryTrafficLightPolicyClearsFixedContentMaxSize() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentMaxSize = NSSize(width: 640, height: 480)
        window.collectionBehavior.insert(.fullScreenNone)

        WindowTrafficLightPolicy.apply(to: window, for: .settings)

        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.resizable))
        #expect(!window.collectionBehavior.contains(.fullScreenNone))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.contentMaxSize.width > 10000)
        #expect(window.contentMaxSize.height > 10000)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isEnabled == true)
        #expect(window.standardWindowButton(.zoomButton)?.isEnabled == true)
        window.close()
    }
    #endif

    @Test("transparent window chrome keeps the NSWindow background clear")
    func transparentWindowChromeKeepsTheNSWindowBackgroundClear() {
        let transparent = WindowAppearancePreferences(
            mode: .glass,
            scope: .mainWindow,
            surfaceOpacity: 0.82
        )
        let solid = WindowAppearancePreferences(
            mode: .solid,
            scope: .mainWindow,
            surfaceOpacity: 0.82
        )

        #expect(transparent.windowBackgroundAlpha(for: .mainWindow, reduceTransparency: false) == 0)
        #expect(transparent.windowBackgroundAlpha(for: .mainWindow, reduceTransparency: true) == 1)
        #expect(solid.windowBackgroundAlpha(for: .mainWindow, reduceTransparency: false) == 1)
    }

    #if os(macOS)
    @Test("translucent main window chrome uses a lighter system material")
    func translucentMainWindowChromeUsesLighterSystemMaterial() {
        #expect(WindowVisualEffectMaterialPolicy.material(for: .frosted, role: .mainWindow) == .sidebar)
        #expect(WindowVisualEffectMaterialPolicy.material(for: .glass, role: .mainWindow) == .sidebar)
        #expect(WindowVisualEffectMaterialPolicy.material(for: .frosted, role: .settings) == .sidebar)
        #expect(WindowVisualEffectMaterialPolicy.material(for: .glass, role: .settings) == .sidebar)
        #expect(WindowVisualEffectMaterialPolicy.material(for: .glass, role: .sidebar) == .sidebar)
        #expect(WindowVisualEffectMaterialPolicy.material(for: .glass, role: .content) == .hudWindow)
    }
    #endif

    @Test("dense reading surfaces avoid live material under translucent modes")
    func denseReadingSurfacesAvoidLiveMaterialUnderTranslucentModes() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows
        )

        #expect(preferences.usesMaterial(for: .mainWindow, reduceTransparency: false) == true)
        #expect(preferences.usesMaterial(for: .sidebar, reduceTransparency: false) == true)
        #expect(preferences.usesMaterial(for: .content, reduceTransparency: false) == false)
        #expect(preferences.usesMaterial(for: .settings, reduceTransparency: false) == true)
        #expect(preferences.usesMaterial(for: .utility, reduceTransparency: false) == true)
        #expect(preferences.usesMaterial(for: .card, reduceTransparency: false) == false)
    }

    @Test("surface opacity follows main window panes without tinting the chrome container")
    func surfaceOpacityFollowsMainWindowPanesWithoutTintingTheChromeContainer() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .mainWindow
        )

        #expect(preferences.usesSurfaceOpacity(for: .mainWindow, reduceTransparency: false) == false)
        #expect(preferences.usesSurfaceOpacity(for: .sidebar, reduceTransparency: false) == true)
        #expect(preferences.usesSurfaceOpacity(for: .content, reduceTransparency: false) == true)
        #expect(preferences.usesSurfaceOpacity(for: .card, reduceTransparency: false) == true)
        #expect(preferences.usesSurfaceOpacity(for: .settings, reduceTransparency: false) == false)
        // Utility windows (e.g. compose) now follow the main window's translucency
        // so they match the rest of the app instead of appearing opaque.
        #expect(preferences.usesSurfaceOpacity(for: .utility, reduceTransparency: false) == true)
    }

    @Test("surface fill opacity avoids stacking pane tint over transparent chrome")
    func surfaceFillOpacityAvoidsStackingPaneTintOverTransparentChrome() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .mainWindow,
            surfaceOpacity: 0.82,
            sidebarOpacity: 0.41
        )

        #expect(preferences.surfaceFillOpacity(for: .mainWindow, reduceTransparency: false) == nil)
        #expect(preferences.surfaceFillOpacity(for: .sidebar, reduceTransparency: false) == 0.41)
        #expect(preferences.surfaceFillOpacity(for: .content, reduceTransparency: false) == 0.82)
        #expect(preferences.surfaceFillOpacity(for: .settings, reduceTransparency: false) == nil)
        #expect(preferences.surfaceFillOpacity(for: .mainWindow, reduceTransparency: true) == 1)
    }

    @Test("sidebar opacity can be tuned separately from dense content opacity")
    func sidebarOpacityCanBeTunedSeparatelyFromDenseContentOpacity() {
        let preferences = WindowAppearancePreferences(
            mode: .frosted,
            scope: .allWindows,
            surfaceOpacity: 0.93,
            sidebarOpacity: 0.22
        )

        #expect(preferences.surfaceFillOpacity(for: .sidebar, reduceTransparency: false) == 0.22)
        #expect(preferences.surfaceFillOpacity(for: .content, reduceTransparency: false) == 0.93)
        #expect(preferences.surfaceFillOpacity(for: .settings, reduceTransparency: false) == nil)
    }

    @Test("message content follows pane opacity by default")
    func messageContentFollowsPaneOpacityByDefault() {
        let preferences = WindowAppearancePreferences(
            mode: .frosted,
            scope: .mainWindow,
            surfaceOpacity: 0.73
        )

        #expect(preferences.surfaceFillOpacity(for: .content, reduceTransparency: false) == 0.73)
        #expect(preferences.surfaceFillOpacity(for: .messageContent, reduceTransparency: false) == 0.73)
    }

    @Test("message content can be opaque without changing pane opacity")
    func messageContentCanBeOpaqueWithoutChangingPaneOpacity() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .mainWindow,
            surfaceOpacity: 0.55,
            messageContentOpacityMode: .opaque
        )

        #expect(preferences.surfaceFillOpacity(for: .content, reduceTransparency: false) == 0.55)
        #expect(preferences.surfaceFillOpacity(for: .messageContent, reduceTransparency: false) == 1)
    }

    @Test("custom message content opacity is independent and clamped through one hundred percent")
    func customMessageContentOpacityIsIndependentAndClamped() {
        let low = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows,
            surfaceOpacity: 0.82,
            messageContentOpacityMode: .custom,
            messageContentOpacity: 0.1
        )
        let high = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows,
            surfaceOpacity: 0.82,
            messageContentOpacityMode: .custom,
            messageContentOpacity: 2
        )

        #expect(low.messageContentOpacity == 0.25)
        #expect(low.surfaceFillOpacity(for: .messageContent, reduceTransparency: false) == 0.25)
        #expect(high.messageContentOpacity == 1)
        #expect(high.surfaceFillOpacity(for: .messageContent, reduceTransparency: false) == 1)
    }

    @Test("omitted sidebar opacity derives from the selected surface opacity")
    func omittedSidebarOpacityDerivesFromSelectedSurfaceOpacity() {
        let preferences = WindowAppearancePreferences(
            mode: .frosted,
            scope: .mainWindow,
            surfaceOpacity: 0.5
        )

        #expect(preferences.sidebarOpacity == 0.36)
        #expect(preferences.surfaceFillOpacity(for: .sidebar, reduceTransparency: false) == 0.36)
    }

    @Test("surface opacity stays on panes instead of secondary window containers")
    func surfaceOpacityStaysOnPanesInsteadOfSecondaryWindowContainers() {
        let preferences = WindowAppearancePreferences(
            mode: .frosted,
            scope: .allWindows
        )

        #expect(preferences.usesSurfaceOpacity(for: .content, reduceTransparency: false) == true)
        #expect(preferences.usesSurfaceOpacity(for: .settings, reduceTransparency: false) == false)
        #expect(preferences.usesSurfaceOpacity(for: .utility, reduceTransparency: false) == true)
    }

    @Test("all-window scope keeps one configured opacity layer per pane")
    func allWindowScopeKeepsOneConfiguredOpacityLayerPerPane() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows,
            surfaceOpacity: 0.25,
            sidebarOpacity: 0.1
        )

        #expect(preferences.surfaceFillOpacity(for: .content, reduceTransparency: false) == 0.25)
        #expect(preferences.surfaceFillOpacity(for: .sidebar, reduceTransparency: false) == 0.1)
        #expect(preferences.surfaceFillOpacity(for: .settings, reduceTransparency: false) == nil)
        #expect(preferences.surfaceFillOpacity(for: .utility, reduceTransparency: false) == 0.25)
    }

    @Test("persisted opacity is clamped to readable material bounds")
    func persistedOpacityIsClampedToReadableMaterialBounds() throws {
        let lowDefaults = try Self.makeDefaults()
        lowDefaults.set(0.1, forKey: WindowAppearancePreferenceKey.surfaceOpacity)
        lowDefaults.set(0.01, forKey: WindowAppearancePreferenceKey.sidebarOpacity)
        let highDefaults = try Self.makeDefaults()
        highDefaults.set(2.0, forKey: WindowAppearancePreferenceKey.surfaceOpacity)
        highDefaults.set(2.0, forKey: WindowAppearancePreferenceKey.sidebarOpacity)

        #expect(WindowAppearancePreferences.load(from: lowDefaults).surfaceOpacity == 0.25)
        #expect(WindowAppearancePreferences.load(from: lowDefaults).sidebarOpacity == 0.1)
        #expect(WindowAppearancePreferences.load(from: highDefaults).surfaceOpacity == 0.95)
        #expect(WindowAppearancePreferences.load(from: highDefaults).sidebarOpacity == 0.95)
    }

    @Test("persisted custom message opacity is clamped to its accessibility bounds")
    func persistedCustomMessageOpacityIsClamped() throws {
        let lowDefaults = try Self.makeDefaults()
        lowDefaults.set("custom", forKey: WindowAppearancePreferenceKey.messageContentOpacityMode)
        lowDefaults.set(0.1, forKey: WindowAppearancePreferenceKey.messageContentOpacity)
        let highDefaults = try Self.makeDefaults()
        highDefaults.set("custom", forKey: WindowAppearancePreferenceKey.messageContentOpacityMode)
        highDefaults.set(2, forKey: WindowAppearancePreferenceKey.messageContentOpacity)

        #expect(WindowAppearancePreferences.load(from: lowDefaults).messageContentOpacity == 0.25)
        #expect(WindowAppearancePreferences.load(from: highDefaults).messageContentOpacity == 1)
    }

    @Test("missing sidebar opacity migrates from the existing surface opacity")
    func missingSidebarOpacityMigratesFromExistingSurfaceOpacity() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(0.5, forKey: WindowAppearancePreferenceKey.surfaceOpacity)

        let preferences = WindowAppearancePreferences.load(from: defaults)

        #expect(preferences.surfaceOpacity == 0.5)
        #expect(preferences.sidebarOpacity == 0.36)
        #expect(preferences.messageContentOpacityMode == .followPane)
        #expect(preferences.messageContentOpacity == 0.5)
    }

    @Test("reduce transparency forces solid surfaces")
    func reduceTransparencyForcesSolidSurfaces() {
        let preferences = WindowAppearancePreferences(
            mode: .glass,
            scope: .allWindows
        )

        #expect(preferences.effectiveMode(reduceTransparency: true) == .solid)
        #expect(preferences.usesMaterial(for: .sidebar, reduceTransparency: true) == false)
        #expect(preferences.usesMaterial(for: .settings, reduceTransparency: true) == false)
        #expect(preferences.usesSurfaceOpacity(for: .content, reduceTransparency: true) == false)
        #expect(preferences.surfaceFillOpacity(for: .messageContent, reduceTransparency: true) == 1)
        #expect(preferences.usesTransparentWindowChrome(for: .mainWindow, reduceTransparency: true) == false)
    }

    @Test("invalid persisted raw values fall back to defaults")
    func invalidPersistedRawValuesFallBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("transparent-chaos", forKey: WindowAppearancePreferenceKey.mode)
        defaults.set("everywhere-and-nowhere", forKey: WindowAppearancePreferenceKey.scope)

        let preferences = WindowAppearancePreferences.load(from: defaults)

        #expect(preferences == .defaults)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "WindowAppearancePreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
