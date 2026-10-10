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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// Compact-layout coverage for the iOS PIM covers — `CalendarRootView`,
/// `ContactsRootView`, `TasksRootView` are presented as full-screen
/// covers from the mailbox surface. The views carry a macOS window
/// minimum (`minWidth: 760`); on iPhone that minimum must not apply or
/// the cover lays out wider than the screen and pushes its own Done
/// affordance offscreen-left (2026-09-27 UI/UX review N-H1).
@Suite("PIM root view compact snapshots")
@MainActor
struct PIMRootViewSnapshotTests {
    private func snapshot(
        _ view: some View,
        named name: String
    ) {
        let theme = BrevTheme.brevPaper
        let host = UIHostingController(rootView: view.brevTheme(theme))
        host.view.backgroundColor = .clear
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES"
                ? .all : nil
        )
    }

    @Test("Calendar cover lays out within iPhone bounds")
    func calendarCoverCompact() {
        snapshot(
            CalendarRootView(model: CalendarBrowsingModel(), onDismiss: {}, onOpenSettings: { _ in }),
            named: "calendar-cover-compact"
        )
    }

    @Test("Contacts cover lays out within iPhone bounds")
    func contactsCoverCompact() {
        snapshot(
            ContactsRootView(model: ContactsBrowsingModel(), onDismiss: {}, onOpenSettings: { _ in }),
            named: "contacts-cover-compact"
        )
    }

    @Test("Tasks cover lays out within iPhone bounds")
    func tasksCoverCompact() {
        snapshot(
            TasksRootView(model: TasksBrowsingModel(), onDismiss: {}, onOpenSettings: { _ in }),
            named: "tasks-cover-compact"
        )
    }
}
#endif
