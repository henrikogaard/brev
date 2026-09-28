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

#if os(macOS) && canImport(WidgetKit)
import AppKit
@testable import BrevWidgets
import SnapshotTesting
import SwiftUI
import Testing
import WidgetKit

@Suite("Mail summary widget snapshots", .serialized)
@MainActor
struct MailSummaryWidgetSnapshotTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var populatedEntry: MailSummaryEntry {
        MailSummaryEntry(
            date: fixedDate,
            snapshot: WidgetSnapshot(
                generatedAt: fixedDate,
                totalUnread: 7,
                previews: [
                    WidgetMessagePreview(
                        senderName: "Ina Nordmann",
                        subject: "Re: Release checklist",
                        receivedAt: fixedDate,
                        accountName: "Privat"
                    ),
                    WidgetMessagePreview(
                        senderName: "Ola Hansen",
                        subject: "Lunch tomorrow?",
                        receivedAt: fixedDate.addingTimeInterval(-3600),
                        accountName: "Work"
                    ),
                    WidgetMessagePreview(
                        senderName: "GitHub",
                        subject: "[brev] New comment on pull request",
                        receivedAt: fixedDate.addingTimeInterval(-7200),
                        accountName: "Work"
                    )
                ]
            )
        )
    }

    @Test("small and medium families render previews in both schemes", arguments: [
        (WidgetFamily.systemSmall, false),
        (WidgetFamily.systemSmall, true),
        (WidgetFamily.systemMedium, false),
        (WidgetFamily.systemMedium, true)
    ])
    func populated(family: WidgetFamily, dark: Bool) {
        let size = widgetSize(for: family)
        let view = MailSummaryWidgetView(entry: populatedEntry, familyOverride: family)
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: size.width, height: size.height)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(origin: .zero, size: size)
        assertSnapshot(
            of: host,
            as: .image(size: size),
            named: "populated-\(family == .systemMedium ? "medium" : "small")-\(dark ? "dark" : "light")",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("medium family renders the empty state", arguments: [false, true])
    func empty(dark: Bool) {
        let size = widgetSize(for: .systemMedium)
        let view = MailSummaryWidgetView(entry: MailSummaryEntry(date: fixedDate, snapshot: nil), familyOverride: .systemMedium)
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: size.width, height: size.height)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(origin: .zero, size: size)
        assertSnapshot(
            of: host,
            as: .image(size: size),
            named: "empty-medium-\(dark ? "dark" : "light")",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// Home-screen size classes: the exact points matter less than
    /// the aspect — 1:1 for small, ~2:1 for medium.
    private func widgetSize(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium:
            CGSize(width: 329, height: 155)
        default:
            CGSize(width: 158, height: 158)
        }
    }
}

#endif
