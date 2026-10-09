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

#if canImport(UIKit)
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Snooze picker snapshots")
@MainActor
struct SnoozePickerSnapshotTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Monday 2026-10-05 10:00 UTC, so every quick option is on offer.
    private static var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10)) ?? .distantPast
    }

    private static func header() -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Marte Solheim", email: "marte@example.org"),
            subject: "Stavanger rollout — terminal go-live window and rollback plan for the weekend",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: false,
            isFlagged: false
        )
    }

    @Test("quick options render as an inset-grouped list", arguments: [false, true])
    func quickOptions(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = SnoozePickerView(
            header: Self.header(),
            sourceID: nil,
            now: Self.now,
            calendar: Self.calendar,
            onConfirm: { _ in },
            onCancel: {}
        )
        .environment(\.locale, Locale(identifier: "en_US"))
        .brevTheme(theme)
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: dark ? "dark" : "light",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("quick options wrap the wake time below the title at accessibility sizes")
    func accessibilitySize() {
        let view = SnoozePickerView(
            header: Self.header(),
            sourceID: nil,
            now: Self.now,
            calendar: Self.calendar,
            onConfirm: { _ in },
            onCancel: {}
        )
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.dynamicTypeSize, .accessibility5)
        .brevTheme(.brevMonoLight)
        let host = UIHostingController(rootView: view)
        let traits = UITraitCollection(traitsFrom: [
            .init(displayScale: 2),
            .init(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ])
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: traits),
            named: "accessibility",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
