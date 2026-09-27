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
import BrevCalendar
@testable import BrevMail
import BrevThemes
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the task detail pane: the read-only explainer
/// rendered when the task's source offers no editing (UI/UX review
/// 2026-09-27 M4/P1). Set `RECORD_SNAPSHOTS=YES` to refresh baselines.
@Suite("Task detail snapshots")
@MainActor
struct TaskDetailSnapshotTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func task() -> PIMTask {
        PIMTask(
            id: "t1",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "t1",
            title: "Ship the release",
            notes: "Coordinate the cutover.",
            status: .needsAction,
            position: nil,
            syncedAt: now
        )
    }

    private static func source() -> PIMSource {
        PIMSource(
            id: "s1",
            kind: .tasks,
            provider: .calDAV,
            displayName: "CalDAV",
            enabledCapabilities: [.read],
            status: .ready,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func collection() -> PIMCollection {
        PIMCollection(
            id: "c1",
            sourceID: "s1",
            kind: .tasks,
            displayName: "Work",
            colorHex: nil,
            isReadOnly: false,
            isPrimary: true,
            supportsSyncToken: true,
            providerKey: "c1",
            providerVersion: nil,
            isVisible: true,
            updatedAt: now
        )
    }

    @Test("task detail explains why editing is hidden", arguments: ["light", "dark"])
    func taskDetailReadOnlyHint(mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = TaskDetailView(
            task: Self.task(),
            collection: Self.collection(),
            source: Self.source()
        )
        .frame(width: 420, height: 400)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 420, height: 400)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 420, height: 400)),
            named: "detail-readonly-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
