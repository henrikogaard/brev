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

@Suite("CalDAVSettings")
struct CalDAVSettingsTests {
    @Test("defaults are disabled with empty server")
    func defaultsAreDisabled() throws {
        let defaults = try Self.makeDefaults()
        let settings = CalDAVSettings.load(from: defaults)

        #expect(settings.isEnabled == false)
        #expect(settings.serverURL.isEmpty)
        #expect(settings.calendarName == "Calendar")
    }

    @Test("saving and loading preserves CalDAV settings")
    func savingAndLoadingPreserves() throws {
        let defaults = try Self.makeDefaults()
        var settings = CalDAVSettings.defaults
        settings.featureFlagEnabled = true
        settings.isEnabled = true
        settings.serverURL = "https://caldav.example.org"
        settings.calendarName = "Work"
        settings.collectionPath = "/calendars/u/work/"
        settings.credentialAccount = "acct-1"

        settings.save(to: defaults)
        let restored = CalDAVSettings.load(from: defaults)

        #expect(restored.featureFlagEnabled == true)
        #expect(restored.isEnabled == true)
        #expect(restored.serverURL == "https://caldav.example.org")
        #expect(restored.calendarName == "Work")
        #expect(restored.collectionPath == "/calendars/u/work/")
        #expect(restored.credentialAccount == "acct-1")
    }

    @Test("feature flag is off by default so the UI stays hidden")
    func featureFlagOffByDefault() throws {
        let defaults = try Self.makeDefaults()
        #expect(CalDAVSettings.load(from: defaults).featureFlagEnabled == false)
    }

    @Test("write target is inactive until flag, enable, server, and path are all set")
    func writeTargetActivation() {
        var settings = CalDAVSettings.defaults
        #expect(settings.isWriteTargetActive == false)
        settings.featureFlagEnabled = true
        settings.isEnabled = true
        #expect(settings.isWriteTargetActive == false) // no server/path yet
        settings.serverURL = "https://caldav.example.org"
        settings.collectionPath = "/calendars/u/work/"
        #expect(settings.isWriteTargetActive == true)
    }

    @Test("collection URL joins server and path preserving trailing slash")
    func collectionURLComposition() {
        var settings = CalDAVSettings.defaults
        settings.serverURL = "https://caldav.example.org"
        settings.collectionPath = "/calendars/u/work/"
        let url = settings.collectionURL
        #expect(url?.absoluteString == "https://caldav.example.org/calendars/u/work/")
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suite = "CalDAVSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
