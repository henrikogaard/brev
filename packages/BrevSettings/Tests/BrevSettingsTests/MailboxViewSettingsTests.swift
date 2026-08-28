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

import BrevDesign
@testable import BrevSettings
import Foundation
import Testing

@Suite("MailboxViewSettings")
struct MailboxViewSettingsTests {
    @Test("defaults match privacy-first mailbox behavior")
    func defaultsMatchPrivacyFirstMailboxBehavior() throws {
        let defaults = try Self.makeDefaults()

        let settings = MailboxViewSettings.load(from: defaults)

        #expect(settings.useRichRenderer == true)
        #expect(settings.allowRemoteContent == false)
        #expect(settings.groupByThread == true)
        #expect(settings.groupByDate == true)
        #expect(settings.showSenderAvatars == true)
        #expect(settings.previewLineCount == .one)
        #expect(settings.fontFamily == .system)
        #expect(settings.textSize == .medium)
        #expect(settings.listDensity == .comfortable)
        #expect(settings.sortOrder == .newestFirst)
        #expect(settings.readingPanePlacement == .side)
        #expect(settings.showFolderStats == true)
        #expect(settings.folderStatsDetail == .compact)
        #expect(settings.showAbsoluteArrivalTime == false)
    }

    @Test("saving and loading preserves every mailbox view option")
    func savingAndLoadingPreservesEveryMailboxViewOption() throws {
        let defaults = try Self.makeDefaults()
        let settings = MailboxViewSettings(
            useRichRenderer: true,
            allowRemoteContent: true,
            groupByThread: false,
            groupByDate: false,
            showAbsoluteArrivalTime: true,
            showSenderAvatars: false,
            previewLineCount: .three,
            fontFamily: .serif,
            textSize: .large,
            listDensity: .compact,
            sortOrder: .oldestFirst,
            threadMessageOrder: .newestFirst,
            readingPanePlacement: .bottom,
            showFolderStats: false,
            folderStatsDetail: .detailed
        )

        settings.save(to: defaults)
        let restored = MailboxViewSettings.load(from: defaults)

        #expect(restored == settings)
    }

    @Test("invalid enum raw values fall back to defaults")
    func invalidEnumRawValuesFallBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("papyrus", forKey: MailboxViewPreferenceKey.fontFamily)
        defaults.set("huge", forKey: MailboxViewPreferenceKey.textSize)
        defaults.set("paper-thin", forKey: MailboxViewPreferenceKey.listDensity)
        defaults.set(99, forKey: MailboxViewPreferenceKey.previewLineCount)
        defaults.set("reverse", forKey: MailboxViewPreferenceKey.sortOrder)
        defaults.set("overlay", forKey: MailboxViewPreferenceKey.readingPanePlacement)
        defaults.set("verbose", forKey: MailboxViewPreferenceKey.folderStatsDetail)

        let settings = MailboxViewSettings.load(from: defaults)

        #expect(settings.fontFamily == .system)
        #expect(settings.textSize == .medium)
        #expect(settings.listDensity == .comfortable)
        #expect(settings.previewLineCount == .one)
        #expect(settings.sortOrder == .newestFirst)
        #expect(settings.readingPanePlacement == .side)
        #expect(settings.folderStatsDetail == .compact)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "MailboxViewSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
