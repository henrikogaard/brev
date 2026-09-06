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

@Suite("Scheduled outbox snapshots")
@MainActor
struct ScheduledOutboxSnapshotTests {
    @Test("scheduled rows distinguish waiting, delivery and review with compact controls", arguments: [false, true])
    func states(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let date = Date(timeIntervalSince1970: 1_788_780_000)
        let entries = [
            PendingScheduledSend(draftID: "waiting", scheduledFor: date, subject: "Monday project update"),
            PendingScheduledSend(draftID: "delivering", scheduledFor: date, subject: "Meeting notes", state: .delivering),
            PendingScheduledSend(
                draftID: "review",
                scheduledFor: date,
                subject: "Proposal for the new office",
                state: .needsReview,
                lastError: "Delivery could not be confirmed. Check Sent before trying again."
            )
        ]
        let view = VStack(alignment: .leading, spacing: 16) {
            ForEach(entries) { entry in
                ScheduledOutboxRow(entry: entry, isBusy: false, canEdit: true, onChange: {}, onCancel: {})
            }
        }
        .padding(16).frame(width: 620, height: 355)
        .background(theme.bgPrimary.color).brevTheme(theme).tint(theme.accent.color)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 620, height: 355)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 620, height: 355)),
                       named: dark ? "scheduled-dark" : "scheduled-light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}
#endif
