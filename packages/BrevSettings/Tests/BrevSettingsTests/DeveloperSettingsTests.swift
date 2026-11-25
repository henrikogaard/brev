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

#if os(macOS)
import AppKit
import Observation
#endif
import BrevPlugins
@testable import BrevSettings
import BrevThemes
import Foundation
import SwiftUI
import Testing

@Suite("Developer settings")
struct DeveloperSettingsTests {
    @Test("defaults keep demo mode and example plugin disabled")
    func defaultsKeepDemoModeDisabled() throws {
        let defaults = try temporaryDefaults()

        let settings = DeveloperSettings.load(from: defaults)

        #expect(settings.demoModeEnabled == false)
        #expect(settings.showExamplePlugin == false)
    }

    @Test("saving demo mode and example plugin flag round-trips through defaults")
    func savingDemoModeRoundTrips() throws {
        let defaults = try temporaryDefaults()

        DeveloperSettings(demoModeEnabled: true, showExamplePlugin: true).save(to: defaults)

        let loaded = DeveloperSettings.load(from: defaults)
        #expect(loaded.demoModeEnabled)
        #expect(loaded.showExamplePlugin)
    }

    @Test("example plugin stays hidden outside developer builds and defaults off in developer builds")
    func examplePluginVisibilityGating() throws {
        let defaults = try temporaryDefaults()
        DeveloperSettings(showExamplePlugin: true).save(to: defaults)

        #expect(DeveloperSettings.isExamplePluginEnabled(
            environment: ["BREV_SHOW_EXAMPLE_PLUGIN": "1"],
            defaults: defaults,
            isDeveloperBuild: false
        ) == false)

        #expect(DeveloperSettings.isExamplePluginEnabled(
            environment: [:],
            defaults: defaults,
            isDeveloperBuild: true
        ))

        #expect(DeveloperSettings.isExamplePluginEnabled(
            environment: ["BREV_SHOW_EXAMPLE_PLUGIN": "0"],
            defaults: defaults,
            isDeveloperBuild: true
        ) == false)

        let freshDefaults = try temporaryDefaults()
        #expect(DeveloperSettings.isExamplePluginEnabled(
            environment: [:],
            defaults: freshDefaults,
            isDeveloperBuild: true
        ) == false)

        let exampleContribution = RegisteredContribution(
            pluginID: DeveloperSettings.examplePluginIdentifier,
            definition: ContributionDefinition(
                id: "settings-panel",
                kind: .settingsPanel,
                displayName: "Example Plugin",
                sfSymbolName: "puzzlepiece.extension"
            )
        )
        let customContribution = RegisteredContribution(
            pluginID: "com.thirdparty.plugin",
            definition: ContributionDefinition(
                id: "custom-settings",
                kind: .settingsPanel,
                displayName: "Custom Plugin",
                sfSymbolName: "gearshape"
            )
        )

        let defaultVisible = SettingsPluginVisibilityPolicy.visibleSettingsContributions(
            [exampleContribution, customContribution],
            isDebugBuild: true,
            defaults: freshDefaults,
            environment: [:]
        )
        #expect(defaultVisible.map(\.pluginID) == ["com.thirdparty.plugin"])

        let enabledVisible = SettingsPluginVisibilityPolicy.visibleSettingsContributions(
            [exampleContribution, customContribution],
            isDebugBuild: true,
            defaults: defaults,
            environment: [:]
        )
        #expect(enabledVisible.map(\.pluginID) == [
            DeveloperSettings.examplePluginIdentifier,
            "com.thirdparty.plugin"
        ])

        // iOS default availability omits the Developer section, yet a DEBUG
        // launch with BREV_SHOW_EXAMPLE_PLUGIN=1 must still surface the panel.
        #expect(SettingsSectionAvailability.v1Default.contains(.developer) == false)
        let iosDebugOptedIn = SettingsPluginVisibilityPolicy.visibleSettingsContributions(
            [exampleContribution, customContribution],
            isDebugBuild: true,
            defaults: freshDefaults,
            environment: ["BREV_SHOW_EXAMPLE_PLUGIN": "1"]
        )
        #expect(iosDebugOptedIn.map(\.pluginID) == [
            DeveloperSettings.examplePluginIdentifier,
            "com.thirdparty.plugin"
        ])

        let releaseOptedIn = SettingsPluginVisibilityPolicy.visibleSettingsContributions(
            [exampleContribution, customContribution],
            isDebugBuild: false,
            defaults: defaults,
            environment: ["BREV_SHOW_EXAMPLE_PLUGIN": "1"]
        )
        #expect(releaseOptedIn.map(\.pluginID) == ["com.thirdparty.plugin"])
    }

    #if os(macOS)
    @Test("dark monochrome themes opt into high-contrast switch styling while light and colored themes stay native")
    func highContrastMonochromeSwitchPolicy() {
        #expect(SettingsToggleRow.usesHighContrastMonochromeSwitch(for: .brevMonoDark))
        #expect(SettingsToggleRow.usesHighContrastMonochromeSwitch(for: .brevMonoGrey))
        #expect(SettingsToggleRow.usesHighContrastMonochromeSwitch(for: .brevMonoLight) == false)
        #expect(SettingsToggleRow.usesHighContrastMonochromeSwitch(for: .brevSlate) == false)
        #expect(SettingsToggleRow.usesHighContrastMonochromeSwitch(for: .brevPaper) == false)
    }

    @Test("dark monochrome high-contrast switch focuses and toggles via Space when enabled and stays unchanged when disabled")
    @MainActor
    func highContrastMonochromeSwitchKeyboardFocusability() throws {
        let enabledBox = SwitchToggleStateBox(isOn: false)
        let enabledHost = makeHostedToggleRow(state: enabledBox, isEnabled: true)
        defer { enabledHost.cleanup() }

        let keyView = try #require(findKeyViewProxy(in: enabledHost.host))
        #expect(enabledHost.window.makeFirstResponder(keyView))
        try sendSpaceKey(to: enabledHost.window)
        #expect(enabledBox.isOn == true)

        try sendSpaceKey(to: enabledHost.window)
        #expect(enabledBox.isOn == false)

        let disabledBox = SwitchToggleStateBox(isOn: false)
        let disabledHost = makeHostedToggleRow(state: disabledBox, isEnabled: false)
        defer { disabledHost.cleanup() }

        #expect(findKeyViewProxy(in: disabledHost.host) == nil)
        try sendSpaceKey(to: disabledHost.window)
        #expect(disabledBox.isOn == false)
    }

    @MainActor
    private func makeHostedToggleRow(
        state: SwitchToggleStateBox,
        isEnabled: Bool
    ) -> (host: NSHostingView<HostedToggleRowHarness>, window: NSWindow, cleanup: () -> Void) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: HostedToggleRowHarness(state: state, isEnabled: isEnabled))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 60)
        let window = SwitchTestKeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return (host, window, {
            window.contentView = nil
            window.close()
        })
    }

    @MainActor
    private func sendSpaceKey(to window: NSWindow) throws {
        let keyDown = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        let keyUp = try #require(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        window.sendEvent(keyDown)
        window.sendEvent(keyUp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor
    private func findKeyViewProxy(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("KeyViewProxy") {
            return view
        }
        for subview in view.subviews {
            if let found = findKeyViewProxy(in: subview) {
                return found
            }
        }
        return nil
    }
    #endif

    @Test("demo launch request is ignored outside developer builds")
    func demoLaunchRequestIsIgnoredOutsideDeveloperBuilds() throws {
        let defaults = try temporaryDefaults()
        DeveloperSettings(demoModeEnabled: true).save(to: defaults)

        #expect(DeveloperSettings.isDemoModeRequested(
            environment: ["BREV_USE_MOCK": "1"],
            defaults: defaults,
            isDeveloperBuild: false
        ) == false)
    }

    @Test("developer builds honor persisted demo mode unless environment overrides it")
    func developerBuildsHonorPersistedDemoMode() throws {
        let defaults = try temporaryDefaults()
        DeveloperSettings(demoModeEnabled: true).save(to: defaults)

        #expect(DeveloperSettings.isDemoModeRequested(
            environment: [:],
            defaults: defaults,
            isDeveloperBuild: true
        ))

        #expect(DeveloperSettings.isDemoModeRequested(
            environment: ["BREV_USE_MOCK": "0"],
            defaults: defaults,
            isDeveloperBuild: true
        ) == false)
    }

    private func temporaryDefaults() throws -> UserDefaults {
        let suiteName = "DeveloperSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

#if os(macOS)
@MainActor
@Observable
private final class SwitchToggleStateBox {
    var isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }
}

private struct HostedToggleRowHarness: View {
    @Bindable var state: SwitchToggleStateBox
    let isEnabled: Bool

    var body: some View {
        SettingsToggleRow(
            symbolName: "eye.slash",
            title: "Remove tracking pixels",
            subtitle: "Strip hidden tracking beacons before displaying messages.",
            isOn: $state.isOn,
            isEnabled: isEnabled
        )
        .frame(width: 480, height: 60)
        .brevTheme(.brevMonoDark)
        .environment(\.colorScheme, .dark)
    }
}

private final class SwitchTestKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
}
#endif
