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
import Foundation
import Testing

@Suite("BrowserSettings")
struct BrowserSettingsTests {
    @Test("defaults use the system browser")
    func defaultsUseSystemBrowser() {
        #expect(BrowserSettings.defaults.preferredBrowser == .systemDefault)
        #expect(BrowserSettings.load().preferredBrowser == .systemDefault)
        #expect(BrowserChoice.systemDefault.title == "Default browser")
    }

    @Test("available browser choices match platform override support")
    func availableBrowserChoicesMatchPlatformOverrideSupport() {
        #expect(BrowserChoice.availableChoices.first == .systemDefault)
        #if os(macOS)
        #expect(BrowserChoice.availableChoices.contains(.safari))
        #else
        #expect(!BrowserChoice.availableChoices.contains(.safari))
        #endif
    }

    @Test("saving and loading preserves the preferred browser")
    func savingAndLoadingPreservesPreferredBrowser() throws {
        let defaults = try Self.makeDefaults()
        let settings = BrowserSettings(preferredBrowser: .firefox)

        settings.save(to: defaults)

        #expect(BrowserSettings.load(from: defaults).preferredBrowser == .firefox)
    }

    @Test("saving and loading preserves a scoped preferred browser")
    func savingAndLoadingPreservesScopedPreferredBrowser() throws {
        let defaults = try Self.makeDefaults()
        let settings = BrowserSettings(preferredBrowser: .edge)

        settings.save(to: defaults, scope: "profile-work")

        #expect(BrowserSettings.load(from: defaults, scope: "profile-work").preferredBrowser == .edge)
        #expect(BrowserSettings.load(from: defaults).preferredBrowser == .systemDefault)
    }

    @Test("corrupt browser data falls back to the default browser")
    func corruptDataFallsBackToDefault() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("not-a-browser", forKey: BrowserSettings.Key.preferredBrowser())

        #expect(BrowserSettings.load(from: defaults).preferredBrowser == .systemDefault)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "BrowserSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
