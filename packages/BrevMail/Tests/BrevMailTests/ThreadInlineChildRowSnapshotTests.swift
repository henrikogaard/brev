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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the selected inline thread-child row.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Thread inline child row snapshots")
@MainActor
struct ThreadInlineChildRowSnapshotTests {
    @Test("selected child row renders as an inset rounded tile")
    func selectedChildRow() {
        let theme = BrevTheme.brevPaper
        let header = MessageHeader(
            id: "inbox:thread-child",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Avery Kim", email: "avery@example.org"),
            subject: "Project update",
            snippet: "The selected child row keeps the same inset selection treatment.",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: true
        )
        // Pinned "now" so the relative date label cannot drift as wall-clock
        // time passes the fixture date, which used to fail this test daily.
        let view = ThreadInlineChildRow(
            header: header,
            isSelected: true,
            onSelect: {},
            referenceDate: header.date.addingTimeInterval(15 * 86400)
        )
        .frame(width: 360, height: 72)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.calendar, Calendar(identifier: .gregorian))
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 72)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 72)),
            named: "selected-child",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
