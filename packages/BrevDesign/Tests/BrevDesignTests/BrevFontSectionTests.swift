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
import Foundation
import Testing

@Suite("Per-section font family (ADR-0086)")
struct BrevFontSectionTests {
    @Test("an explicit section choice wins over the legacy message font")
    func sectionKeyWins() {
        for section in BrevFontSection.allCases {
            #expect(section.resolve(sectionRaw: "serif", legacyRaw: "monospaced") == .serif)
        }
    }

    @Test("list and reader inherit the legacy message font when unset")
    func mailSectionsInheritLegacyFont() {
        #expect(BrevFontSection.messageList.resolve(sectionRaw: nil, legacyRaw: "monospaced") == .monospaced)
        #expect(BrevFontSection.reader.resolve(sectionRaw: "", legacyRaw: "rounded") == .rounded)
    }

    @Test("the sidebar ignores the legacy message font")
    func sidebarIgnoresLegacyFont() {
        #expect(BrevFontSection.sidebar.resolve(sectionRaw: nil, legacyRaw: "monospaced") == .system)
    }

    @Test("unknown or missing values fall back to System")
    func unknownValuesFallBack() {
        #expect(BrevFontSection.reader.resolve(sectionRaw: "comic", legacyRaw: "nope") == .system)
        #expect(BrevFontSection.messageList.resolve(sectionRaw: nil, legacyRaw: nil) == .system)
    }

    @Test("resolvedFamily reads the section and legacy keys from defaults")
    func resolvesFromDefaults() throws {
        let suite = "BrevFontSectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(MailboxFontFamily.serif.rawValue, forKey: MailboxViewPreferenceKey.fontFamily)
        defaults.set(MailboxFontFamily.rounded.rawValue, forKey: BrevFontSection.sidebar.preferenceKey)

        #expect(BrevFontSection.sidebar.resolvedFamily(in: defaults) == .rounded)
        #expect(BrevFontSection.messageList.resolvedFamily(in: defaults) == .serif)
        #expect(BrevFontSection.reader.resolvedFamily(in: defaults) == .serif)
    }

    @Test("each section has its own preference key")
    func distinctKeys() {
        let keys = Set(BrevFontSection.allCases.map(\.preferenceKey))
        #expect(keys.count == BrevFontSection.allCases.count)
        #expect(!keys.contains(MailboxViewPreferenceKey.fontFamily))
    }
}
