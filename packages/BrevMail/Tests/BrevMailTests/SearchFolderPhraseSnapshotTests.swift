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

#if os(macOS)
import AppKit
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for removable folder-phrase search chips (#296).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Search folder phrase snapshots")
@MainActor
struct SearchFolderPhraseSnapshotTests {
    @Test("folder phrase query chips render in English and Norwegian queries", arguments: ["light", "dark"])
    func folderPhraseChips(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 0))!
        let sentPlan = NaturalLanguageSearchPlanner.plan(
            for: "receipt in Sent",
            execution: .cacheOnly,
            now: now,
            calendar: calendar
        )
        let norwegianPlan = NaturalLanguageSearchPlanner.plan(
            for: "kvittering i Arkiv",
            execution: .cacheOnly,
            now: now,
            calendar: calendar
        )
        #expect(sentPlan.chips.contains { $0.kind == .folder })
        #expect(norwegianPlan.chips.contains { $0.kind == .folder })

        let view = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                NaturalLanguageSearchChipStrip(chips: sentPlan.chips, onRemove: { _ in })
            }
            HStack(spacing: 6) {
                NaturalLanguageSearchChipStrip(chips: norwegianPlan.chips, onRemove: { _ in })
            }
        }
        .padding(16)
        .frame(width: 420, height: 100, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 420, height: 100)),
            named: "search-folder-chips-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
