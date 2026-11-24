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
        #expect(settings.allowRemoteContentForTrustedSenders == false)
        #expect(settings.stripTrackingPixels == true)
        #expect(settings.groupByThread == true)
        #expect(settings.groupByDate == true)
        #expect(settings.showSenderAvatars == true)
        #expect(settings.previewLineCount == .one)
        #expect(settings.fontFamily == .system)
        #expect(settings.textSize == .medium)
        // ADR-0085: the platform default is .compact on macOS, .comfortable on iOS.
        #expect(settings.listDensity == MailboxListDensity.platformDefault)
        #expect(settings.sortOrder == .newestFirst)
        #expect(settings.readingPanePlacement == .side)
        #expect(settings.showFolderStats == false)
        #expect(settings.folderStatsDetail == .compact)
        #expect(settings.showAbsoluteArrivalTime == false)
    }

    @Test("saving and loading preserves every mailbox view option")
    func savingAndLoadingPreservesEveryMailboxViewOption() throws {
        let defaults = try Self.makeDefaults()
        let settings = MailboxViewSettings(
            useRichRenderer: true,
            allowRemoteContent: true,
            allowRemoteContentForTrustedSenders: true,
            stripTrackingPixels: false,
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

    @Test("older settings backups default tracking-pixel removal on")
    func olderSettingsBackupsDefaultTrackingPixelRemovalOn() throws {
        let currentMailboxView = try JSONEncoder().encode(MailboxViewSettings.defaults)
        var oldMailboxView = try #require(
            JSONSerialization.jsonObject(with: currentMailboxView) as? [String: Any]
        )
        oldMailboxView.removeValue(forKey: "stripTrackingPixels")
        let oldBackup = try JSONSerialization.data(withJSONObject: ["mailboxView": oldMailboxView])

        let payload = try JSONDecoder().decode(SettingsBackupPayload.self, from: oldBackup)

        #expect(payload.mailboxView?.stripTrackingPixels == true)
    }

    @Test("older settings backups default trusted-sender remote images off")
    func olderSettingsBackupsDefaultTrustedSenderRemoteImagesOff() throws {
        let currentMailboxView = try JSONEncoder().encode(MailboxViewSettings.defaults)
        var oldMailboxView = try #require(
            JSONSerialization.jsonObject(with: currentMailboxView) as? [String: Any]
        )
        oldMailboxView.removeValue(forKey: "allowRemoteContentForTrustedSenders")
        let oldBackup = try JSONSerialization.data(withJSONObject: ["mailboxView": oldMailboxView])

        let payload = try JSONDecoder().decode(SettingsBackupPayload.self, from: oldBackup)

        #expect(payload.mailboxView?.allowRemoteContentForTrustedSenders == false)
    }

    @Test("trusted-sender remote image setting round-trips through SettingsBackupCodec and stays off iCloud allowlist")
    func trustedSenderSettingRoundTripsThroughBackupAndExcludedFromPreferenceSync() throws {
        let sourceDefaults = try Self.makeDefaults()
        let targetDefaults = try Self.makeDefaults()
        let sourceStore = SettingsPersistenceStore(defaults: sourceDefaults)
        let targetStore = SettingsPersistenceStore(defaults: targetDefaults)

        var updated = sourceStore.mailboxViewSettings()
        updated.allowRemoteContentForTrustedSenders = true
        sourceStore.save(updated)

        let payload = SettingsBackupCodec.export(from: sourceStore)
        #expect(payload.mailboxView?.allowRemoteContentForTrustedSenders == true)

        SettingsBackupCodec.apply(payload, to: targetStore, mode: .replace)
        #expect(targetStore.mailboxViewSettings().allowRemoteContentForTrustedSenders == true)

        // Network-consent flags never mirror silently through iCloud preference sync.
        #expect(!PreferenceSyncAllowlist.keys.contains(MailboxViewPreferenceKey.allowRemoteContent))
        #expect(!PreferenceSyncAllowlist.keys.contains(MailboxViewPreferenceKey.allowRemoteContentForTrustedSenders))
    }

    @Test("trusted-sender privacy copy is translated to Norwegian")
    func trustedSenderPrivacyCopyHasNorwegianTranslations() throws {
        let strings = try Self.loadSettingsCatalogStrings()
        for key in [
            "Load remote images for trusted senders",
            "Automatically load remote images from your Contacts and people you have emailed. Known tracking pixels remain blocked.",
            "Automatically load remote images from your Contacts and people you have emailed. Tracking-pixel removal is currently off.",
            "Remote images load automatically for trusted senders; unknown senders stay blocked."
        ] {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            let norwegian = localizations?["nb"] as? [String: Any]
            let unit = norwegian?["stringUnit"] as? [String: Any]
            #expect(unit?["state"] as? String == "translated", "missing nb for \(key)")
            #expect((unit?["value"] as? String)?.isEmpty == false, "empty nb for \(key)")
        }
    }

    @Test("trusted-sender subtitle reflects whether tracking-pixel removal is enabled")
    func trustedSenderSubtitleReflectsTrackingPixelToggle() {
        let whenStrippingOn = PrivacySection.trustedSendersSubtitle(stripTrackingPixels: true)
        let whenStrippingOff = PrivacySection.trustedSendersSubtitle(stripTrackingPixels: false)

        #expect(whenStrippingOn.contains("Known tracking pixels remain blocked"))
        #expect(!whenStrippingOff.contains("Known tracking pixels remain blocked"))
        #expect(whenStrippingOff.contains("Tracking-pixel removal is currently off"))
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
        #expect(settings.listDensity == MailboxListDensity.platformDefault)
        #expect(settings.previewLineCount == .one)
        #expect(settings.sortOrder == .newestFirst)
        #expect(settings.readingPanePlacement == .side)
        #expect(settings.folderStatsDetail == .compact)
    }

    @Test("tracking-pixel privacy copy is translated to Norwegian")
    func trackingPixelPrivacyCopyHasNorwegianTranslations() throws {
        let strings = try Self.loadSettingsCatalogStrings()
        for key in [
            "Remove tracking pixels",
            "Remove likely tracking images before they render, even when remote content is allowed.",
            "Images and web fonts stay blocked until you allow remote content; likely tracking images are removed by default."
        ] {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            let norwegian = localizations?["nb"] as? [String: Any]
            let unit = norwegian?["stringUnit"] as? [String: Any]
            #expect(unit?["state"] as? String == "translated", "missing nb for \(key)")
            #expect((unit?["value"] as? String)?.isEmpty == false, "empty nb for \(key)")
        }
    }

    @Test("BrevSettings and BrevMail share the tracking-pixel preference key")
    func trackingPixelPreferenceKeyMatchesBrevMail() throws {
        let settingsKey = try Self.stringConstant(
            named: "stripTrackingPixels",
            relativePath: "packages/BrevSettings/Sources/BrevSettings/MailboxViewSettings.swift"
        )
        let mailKey = try Self.stringConstant(
            named: "storageKey",
            relativePath: "packages/BrevMail/Sources/BrevMail/MessageTrackerNote.swift"
        )

        #expect(settingsKey == "body.stripTrackingPixels")
        #expect(mailKey == settingsKey)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "MailboxViewSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func loadSettingsCatalogStrings() throws -> [String: Any] {
        let relativePath = "packages/BrevSettings/Sources/BrevSettings/Resources/Localizable.xcstrings"
        let data = try Data(contentsOf: Self.repositoryFile(relativePath))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(root?["strings"] as? [String: Any])
    }

    private static func stringConstant(named name: String, relativePath: String) throws -> String {
        let source = try String(contentsOf: Self.repositoryFile(relativePath), encoding: .utf8)
        let pattern = "static let \(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*\"([^\"]+)\""
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              let valueRange = Range(match.range(at: 1), in: source) else {
            throw CatalogLookupError.notFound
        }
        return String(source[valueRange])
    }

    private static func repositoryFile(_ relativePath: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw CatalogLookupError.notFound
    }

    private enum CatalogLookupError: Error {
        case notFound
    }
}
