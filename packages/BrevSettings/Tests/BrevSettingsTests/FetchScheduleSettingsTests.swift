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

@Suite("FetchScheduleSettings")
struct FetchScheduleSettingsTests {
    @Test("defaults are manual")
    func defaultsAreManual() throws {
        let defaults = try Self.makeDefaults()
        let settings = FetchScheduleSettings.load(from: defaults)

        #expect(settings.interval == .manual)
    }

    @Test("saving and loading preserves fetch settings")
    func savingAndLoadingPreserves() throws {
        let defaults = try Self.makeDefaults()
        var settings = FetchScheduleSettings.defaults
        settings.interval = .fifteenMinutes

        settings.save(to: defaults)
        let restored = FetchScheduleSettings.load(from: defaults)

        #expect(restored.interval == .fifteenMinutes)
    }

    @Test("corrupt persisted data falls back to defaults")
    func corruptDataFallsBack() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("warp-speed", forKey: FetchScheduleSettings.Key.interval)

        let settings = FetchScheduleSettings.load(from: defaults)
        #expect(settings.interval == FetchScheduleSettings.defaults.interval)
    }

    @Test("fetch intervals provide correct seconds")
    func fetchIntervalsProvideCorrectSeconds() {
        #expect(FetchInterval.manual.intervalSeconds == nil)
        #expect(FetchInterval.fiveMinutes.intervalSeconds == 300)
        #expect(FetchInterval.fifteenMinutes.intervalSeconds == 900)
        #expect(FetchInterval.thirtyMinutes.intervalSeconds == 1800)
        #expect(FetchInterval.oneHour.intervalSeconds == 3600)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suite = "FetchScheduleSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
