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

@Suite("Settings search on iPhone")
struct SettingsSearchPlatformTests {
    @Test("rows that only exist on Mac are not searchable on iPhone")
    func macOnlyRowsAreDropped() {
        let titles = SettingsSection.notifications.searchableControlTitles
            + SettingsSection.mailStorage.searchableControlTitles
            + SettingsSection.calendarContacts.searchableControlTitles
            + SettingsSection.importExport.searchableControlTitles
        let adjusted = SettingsSearchPlatformAdjustment.iOSTitles(from: titles)
        for macOnly in ["Show dock badge", "Cache location", "Capabilities and roadmap", "Import mail"] {
            #expect(!adjusted.contains(macOnly), "\(macOnly) should not be searchable on iPhone")
        }
    }

    @Test("the badge row is searchable under its iPhone name")
    func badgeRowIsRenamed() {
        let adjusted = SettingsSearchPlatformAdjustment.iOSTitles(from: ["Show dock badge", "Quiet hours"])
        #expect(adjusted == ["App icon badge", "Quiet hours"])
    }

    @Test("titles that exist on both platforms are untouched")
    func sharedTitlesSurvive() {
        let shared = ["Enable notifications", "Size on disk", "Export mail"]
        #expect(SettingsSearchPlatformAdjustment.iOSTitles(from: shared) == shared)
    }
}
