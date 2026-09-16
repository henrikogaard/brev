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
@testable import BrevMail
import BrevThemes
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the menu-bar status content (ADR-0075).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Background mail status snapshots")
@MainActor
struct BackgroundMailStatusViewSnapshotTests {
    private static let lastCheck = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("in-flight check reports Checking", arguments: ["light", "dark"])
    func checking(mode: String) {
        assertStatus(
            presentation: BackgroundMailStatusPresentation(
                unreadCount: 3,
                isRefreshing: true
            ),
            named: "checking-\(mode)",
            mode: mode
        )
    }

    @Test("successful check reports the time", arguments: ["light", "dark"])
    func lastChecked(mode: String) {
        assertStatus(
            presentation: BackgroundMailStatusPresentation(
                unreadCount: 0,
                lastSuccessfulRefresh: Self.lastCheck
            ),
            named: "last-checked-\(mode)",
            mode: mode
        )
    }

    @Test("failed check surfaces the provider-neutral summary", arguments: ["light", "dark"])
    func failed(mode: String) {
        assertStatus(
            presentation: BackgroundMailStatusPresentation(
                unreadCount: 1,
                lastFailureSummary: "Connection timed out"
            ),
            named: "failed-\(mode)",
            mode: mode
        )
    }

    @Test("manual schedule discloses push-only listening", arguments: ["light", "dark"])
    func manual(mode: String) {
        assertStatus(
            presentation: BackgroundMailStatusPresentation(
                unreadCount: 0,
                isManualSchedule: true
            ),
            named: "manual-\(mode)",
            mode: mode
        )
    }

    private func assertStatus(
        presentation: BackgroundMailStatusPresentation,
        named name: String,
        mode: String
    ) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = BackgroundMailStatusView(
            presentation: presentation,
            onCheckNow: {},
            onOpenBrev: {},
            onQuitBrev: {}
        )
        .frame(width: 320)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 160)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 320, height: 160)),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
