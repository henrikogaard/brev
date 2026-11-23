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
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for the Mailbox View "Single-key shortcuts" toggle (#300).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Mailbox View single-key shortcuts snapshots")
@MainActor
struct MailboxViewShortcutsSnapshotTests {
    @Test("MailboxViewSection renders Single-key shortcuts toggle", arguments: ["light", "dark"])
    func mailboxViewSingleKeyToggle(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suiteName = "MailboxViewShortcutsSnapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let view = MailboxViewSection(settingsStore: SettingsPersistenceStore(defaults: defaults))
            .frame(width: 640, height: 1180)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .environment(\.colorScheme, theme.mode.colorScheme)
            .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 640, height: 1180)),
            named: "mailbox-view-shortcuts-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
