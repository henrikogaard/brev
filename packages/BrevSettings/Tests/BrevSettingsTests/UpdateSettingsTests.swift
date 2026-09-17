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

@Suite("UpdateSettings")
struct UpdateSettingsTests {
    @Test("defaults use once-per-launch checks")
    func defaultsUseOncePerLaunchChecks() throws {
        let defaults = try Self.makeDefaults()
        let settings = UpdateSettings.load(from: defaults)

        #expect(settings.cadence == .oncePerLaunch)
        #expect(settings.automaticallyChecksForUpdates)
        #expect(settings.scheduledCheckInterval == 86400)
    }

    @Test("rings expose their default appcasts and download links")
    func ringDefaults() {
        #expect(UpdateRing.stable.appcastURL.absoluteString
            == "https://henrikogaard.github.io/brev/appcast.xml")
        #expect(UpdateRing.nightly.appcastURL.absoluteString
            == "https://henrikogaard.github.io/brev/appcast-nightly.xml")
        #expect(UpdateRing.stable.otherRingDownloadURL.absoluteString
            == "https://github.com/henrikogaard/brev/releases/tag/nightly")
        #expect(UpdateRing.nightly.otherRingDownloadURL.absoluteString
            == "https://github.com/henrikogaard/brev/releases/latest")
    }

    @Test("a leftover updates.channel default is ignored")
    func leftoverChannelDefaultIsIgnored() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("beta", forKey: "updates.channel")

        let settings = UpdateSettings.load(from: defaults)

        #expect(settings == .defaults)
    }

    @Test("manual cadence disables automatic checks")
    func manualCadenceDisablesAutomaticChecks() {
        let settings = UpdateSettings(cadence: .manual)

        #expect(!settings.automaticallyChecksForUpdates)
        #expect(settings.scheduledCheckInterval == 0)
        #expect(!settings.startsUpdaterOnLaunch)
    }

    @Test("automatic cadence starts updater on launch")
    func automaticCadenceStartsUpdaterOnLaunch() {
        #expect(UpdateSettings(cadence: .oncePerLaunch).startsUpdaterOnLaunch)
        #expect(UpdateSettings(cadence: .weekly).startsUpdaterOnLaunch)
    }

    @Test("saving and loading preserves update settings")
    func savingAndLoadingPreservesUpdateSettings() throws {
        let defaults = try Self.makeDefaults()
        let settings = UpdateSettings(cadence: .weekly)

        settings.save(to: defaults)
        let restored = UpdateSettings.load(from: defaults)

        #expect(restored == settings)
    }

    @Test("corrupt stored values fall back to defaults")
    func corruptStoredValuesFallBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("hourly-ish", forKey: UpdateSettings.Key.cadence)

        let settings = UpdateSettings.load(from: defaults)

        #expect(settings == .defaults)
    }

    @Test("BRReleaseRing parses stable, nightly, and garbage")
    func releaseRingParsesFromInfoPlist() {
        func ring(_ value: String?) -> UpdateRing {
            var dictionary: [String: Any] = [:]
            if let value { dictionary["BRReleaseRing"] = value }
            return UpdateBuildConfiguration(infoDictionary: dictionary, platform: .macOS).ring
        }

        #expect(ring(nil) == .stable)
        #expect(ring("stable") == .stable)
        #expect(ring("nightly") == .nightly)
        #expect(ring("beta") == .stable)
        #expect(ring("") == .stable)
    }

    @Test("appcast URL prefers local override, then plist feed, then ring default")
    func appcastURLPrecedence() {
        let ringDefault = UpdateBuildConfiguration(
            infoDictionary: ["BRReleaseRing": "nightly"],
            environment: [:],
            platform: .macOS
        )
        #expect(ringDefault.appcastURL == UpdateRing.nightly.appcastURL)

        let plistFeed = UpdateBuildConfiguration(
            infoDictionary: ["SUFeedURL": "https://example.org/custom.xml"],
            environment: [:],
            platform: .macOS
        )
        #expect(plistFeed.appcastURL.absoluteString == "https://example.org/custom.xml")

        let localOverride = UpdateBuildConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://example.org/custom.xml",
                "BRReleaseRing": "nightly"
            ],
            environment: ["BREV_LOCAL_APPCAST_URL": "http://127.0.0.1:8765/appcast.xml"],
            platform: .macOS
        )
        #expect(localOverride.appcastURL.absoluteString == "http://127.0.0.1:8765/appcast.xml")
    }

    @Test("build policy initializes Sparkle only for configured direct-download macOS builds")
    func buildPolicyInitializesSparkleOnlyForConfiguredDirectDownloadMacOSBuilds() {
        let configured = UpdateBuildConfiguration(
            platform: .macOS,
            distribution: .directDownload,
            feedURL: URL(string: "https://henrikogaard.github.io/brev/appcast.xml"),
            publicEDKey: "valid-public-ed-key"
        )
        let missingKey = UpdateBuildConfiguration(
            platform: .macOS,
            distribution: .directDownload,
            feedURL: URL(string: "https://henrikogaard.github.io/brev/appcast.xml"),
            publicEDKey: "BREV_SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER"
        )
        let appStore = UpdateBuildConfiguration(
            platform: .macOS,
            distribution: .appStore,
            feedURL: configured.feedURL,
            publicEDKey: configured.publicEDKey
        )
        let iOS = UpdateBuildConfiguration(
            platform: .iOS,
            distribution: .appStore,
            feedURL: configured.feedURL,
            publicEDKey: configured.publicEDKey
        )

        #expect(configured.canInitializeSparkle)
        #expect(!missingKey.canInitializeSparkle)
        #expect(!appStore.canInitializeSparkle)
        #expect(!iOS.canInitializeSparkle)
    }

    @Test("Info plist parsing rejects unresolved build settings")
    func infoPlistParsingRejectsUnresolvedBuildSettings() {
        let config = UpdateBuildConfiguration(
            infoDictionary: [
                "BRDistributionChannel": "direct-download",
                "SUFeedURL": "https://henrikogaard.github.io/brev/appcast.xml",
                "SUPublicEDKey": "$(BREV_SPARKLE_PUBLIC_ED_KEY)"
            ],
            platform: .macOS
        )

        #expect(config.distribution == .directDownload)
        #expect(config.feedURL?.absoluteString == "https://henrikogaard.github.io/brev/appcast.xml")
        #expect(!config.hasConfiguredPublicEDKey)
        #expect(!config.canInitializeSparkle)
    }

    @Test("local appcast override accepts loopback URLs for Sparkle QA")
    func localAppcastOverrideAcceptsLoopbackURLsForSparkleQA() {
        let config = UpdateBuildConfiguration(
            infoDictionary: [
                "BRDistributionChannel": "direct-download",
                "SUFeedURL": "https://henrikogaard.github.io/brev/appcast.xml",
                "SUPublicEDKey": "test-public-key"
            ],
            environment: [
                "BREV_LOCAL_APPCAST_URL": "http://127.0.0.1:8765/appcast.xml"
            ],
            platform: .macOS
        )

        #expect(config.localAppcastURL?.absoluteString == "http://127.0.0.1:8765/appcast.xml")
        #expect(config.appcastURL.absoluteString == "http://127.0.0.1:8765/appcast.xml")
        #expect(config.canInitializeSparkle)
    }

    @Test("local appcast override accepts loopback URLs from Info plist")
    func localAppcastOverrideAcceptsLoopbackURLsFromInfoPlist() {
        let config = UpdateBuildConfiguration(
            infoDictionary: [
                "BRDistributionChannel": "direct-download",
                "SUFeedURL": "https://henrikogaard.github.io/brev/appcast.xml",
                "SUPublicEDKey": "test-public-key",
                "BRLocalAppcastURL": "http://localhost:8765/appcast.xml"
            ],
            environment: [:],
            platform: .macOS
        )

        #expect(config.localAppcastURL?.absoluteString == "http://localhost:8765/appcast.xml")
        #expect(config.appcastURL.absoluteString == "http://localhost:8765/appcast.xml")
    }

    @Test("local appcast override rejects non loopback URLs")
    func localAppcastOverrideRejectsNonLoopbackURLs() {
        let config = UpdateBuildConfiguration(
            infoDictionary: [
                "BRDistributionChannel": "direct-download",
                "SUFeedURL": "https://henrikogaard.github.io/brev/appcast.xml",
                "SUPublicEDKey": "test-public-key",
                "BRLocalAppcastURL": "https://updates.example.invalid/appcast.xml"
            ],
            environment: [:],
            platform: .macOS
        )

        #expect(config.localAppcastURL == nil)
        #expect(config.appcastURL.absoluteString == "https://henrikogaard.github.io/brev/appcast.xml")
    }

    @Test("local appcast override rejects hostnames that merely start with 127")
    func localAppcastOverrideRejectsHostnamesThatMerelyStartWith127() {
        let config = UpdateBuildConfiguration(
            infoDictionary: [
                "BRDistributionChannel": "direct-download",
                "SUFeedURL": "https://henrikogaard.github.io/brev/appcast.xml",
                "SUPublicEDKey": "test-public-key"
            ],
            environment: [
                "BREV_LOCAL_APPCAST_URL": "http://127.example.invalid/appcast.xml"
            ],
            platform: .macOS
        )

        #expect(config.localAppcastURL == nil)
    }

    @Test("manual check action only runs when updates are available")
    @MainActor
    func manualCheckActionOnlyRunsWhenUpdatesAreAvailable() {
        var checkCount = 0
        let available = SettingsUpdateActions(
            isManualCheckAvailable: true,
            checkForUpdates: { checkCount += 1 },
            settingsDidChange: { _ in }
        )
        let unavailable = SettingsUpdateActions(
            isManualCheckAvailable: false,
            checkForUpdates: { checkCount += 1 },
            settingsDidChange: { _ in }
        )

        available.performManualCheckIfAvailable()
        unavailable.performManualCheckIfAvailable()

        #expect(checkCount == 1)
    }

    @Test("GitHub release checks are manual only")
    func githubReleaseChecksAreManualOnly() {
        #expect(!GitHubReleaseCheckPolicy.shouldRunOnSettingsOpen)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "UpdateSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
