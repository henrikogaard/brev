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

@Suite("FetchSchedulePresentation")
struct FetchSchedulePresentationTests {
    @Test("manual interval subtitle mentions manual-only mode")
    func manualIntervalSubtitleMentionsManualMode() {
        let subtitle = FetchSchedulePresentation.intervalSubtitle(.manual)
        #expect(subtitle.localizedLowercase.contains("refresh")
            || subtitle.localizedLowercase.contains("check")
            || subtitle.localizedLowercase.contains("manual"))
    }

    /// The subtitle no longer claims anything about background checks — Brev
    /// has no background-fetch scheduler, so the old "Background checks
    /// included/disabled" sentence described a setting that never ran.
    @Test("subtitle makes no background-fetch claim")
    func subtitleMakesNoBackgroundClaim() {
        for interval in FetchInterval.allCases {
            let subtitle = FetchSchedulePresentation.intervalSubtitle(interval)
            #expect(!subtitle.localizedLowercase.contains("background"))
        }
    }

    @Test("subtitle is non-empty for every interval")
    func subtitleIsNonEmptyForAllIntervals() {
        for interval in FetchInterval.allCases {
            #expect(!FetchSchedulePresentation.intervalSubtitle(interval).isEmpty)
        }
    }
}
