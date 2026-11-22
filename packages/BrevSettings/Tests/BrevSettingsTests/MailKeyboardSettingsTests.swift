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

@Suite("Single-key shortcut setting")
@MainActor
struct MailKeyboardSettingsTests {
    private static let title = "Single-key shortcuts"
    private static let subtitle = "With the message list focused: E archive, R reply, S star, # delete, H snooze, J and K next and previous. Never while typing."

    @Test("the Mac-only row is searchable on Mac and hidden on iPhone")
    func search() {
        #if os(macOS)
        #expect(SettingsSection.mailboxView.searchableControlTitles.contains(Self.title))
        #endif
        #expect(!SettingsSearchPlatformAdjustment.iOSTitles(from: [Self.title]).contains(Self.title))
    }

    @Test("defaults on and persists the device-local choice")
    func storedPreference() throws {
        let defaults = try #require(UserDefaults(suiteName: "MailKeyboardSettingsTests"))
        defaults.removePersistentDomain(forName: "MailKeyboardSettingsTests")
        #expect(MailKeyboardPreferences.singleKeyShortcutsEnabled(in: defaults))
        defaults.set(false, forKey: MailKeyboardPreferences.singleKeyShortcuts)
        #expect(!MailKeyboardPreferences.singleKeyShortcutsEnabled(in: defaults))
    }

    @Test("the row copy has Norwegian catalog entries")
    func catalog() throws {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var catalogURL: URL?
        for _ in 0 ..< 7 {
            let candidate = directory
                .appendingPathComponent("packages/BrevSettings/Sources/BrevSettings/Resources/Localizable.xcstrings")
            if FileManager.default.fileExists(atPath: candidate.path) { catalogURL = candidate }
            directory.deleteLastPathComponent()
        }
        let data = try Data(contentsOf: #require(catalogURL))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        for key in [Self.title, Self.subtitle] {
            let entry = strings[key] as? [String: Any]
            let nb = (entry?["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            #expect((nb?["stringUnit"] as? [String: Any])?["value"] as? String != nil, "missing nb for \(key)")
        }
    }
}
