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

@Suite("EncryptionSettings")
struct EncryptionSettingsTests {
    @Test("defaults are all disabled")
    func defaultsAreAllDisabled() throws {
        let defaults = try Self.makeDefaults()
        let settings = EncryptionSettings.load(from: defaults)

        #expect(settings.smimeEnabled == false)
        #expect(settings.preferSign == false)
        #expect(settings.preferEncrypt == false)
    }

    @Test("saving and loading preserves encryption settings")
    func savingAndLoadingPreserves() throws {
        let defaults = try Self.makeDefaults()
        var settings = EncryptionSettings.defaults
        settings.smimeEnabled = true
        settings.preferSign = true

        settings.save(to: defaults)
        let restored = EncryptionSettings.load(from: defaults)

        #expect(restored.smimeEnabled == true)
        #expect(restored.preferSign == true)
        #expect(restored.preferEncrypt == false)
    }

    @Test("corrupt persisted encryption data falls back to defaults")
    func corruptDataFallsBack() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("not-a-bool", forKey: EncryptionSettings.Key.smimeEnabled)

        let settings = EncryptionSettings.load(from: defaults)
        #expect(settings.smimeEnabled == EncryptionSettings.defaults.smimeEnabled)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suite = "EncryptionSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
