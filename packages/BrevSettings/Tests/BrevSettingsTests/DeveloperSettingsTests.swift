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

@Suite("Developer settings")
struct DeveloperSettingsTests {
    @Test("defaults keep demo mode disabled")
    func defaultsKeepDemoModeDisabled() throws {
        let defaults = try temporaryDefaults()

        let settings = DeveloperSettings.load(from: defaults)

        #expect(settings.demoModeEnabled == false)
    }

    @Test("saving demo mode round-trips through defaults")
    func savingDemoModeRoundTrips() throws {
        let defaults = try temporaryDefaults()

        DeveloperSettings(demoModeEnabled: true).save(to: defaults)

        #expect(DeveloperSettings.load(from: defaults).demoModeEnabled)
    }

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
