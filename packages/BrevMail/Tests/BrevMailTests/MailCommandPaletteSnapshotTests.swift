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
import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for the ⌘K command palette (#300).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Command palette snapshots")
@MainActor
struct MailCommandPaletteSnapshotTests {
    @Test("command palette renders commands, workspace destinations, mailboxes, and settings", arguments: ["light", "dark"])
    func palettePresentation(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let entries = [
            MailPaletteEntry("About Brev", detail: "Brev", category: .appAndWindow) {},
            MailPaletteEntry("Quit Brev", detail: "Brev", category: .appAndWindow, shortcutKeycaps: ["⌘", "Q"]) {},
            MailPaletteEntry("New Message", detail: "File", shortcutKeycaps: ["⌘", "N"]) {},
            MailPaletteEntry("Reply", detail: "Message", shortcutKeycaps: ["⌘", "R"]) {},
            MailPaletteEntry("Archive", detail: "Message", shortcutKeycaps: ["⌘", "E"]) {},
            MailPaletteEntry("Get New Mail", detail: "File", shortcutKeycaps: ["⌥", "⌘", "R"]) {},
            MailPaletteEntry("Assistant", detail: "Mailbox", category: .jumpTo, emptyQueryPriority: 10) {},
            MailPaletteEntry("Today", detail: "Mailbox", category: .jumpTo, emptyQueryPriority: 20) {},
            MailPaletteEntry("Inbox", detail: "Mailbox · Work · primary@example.org", category: .jumpTo,
                             emptyQueryPriority: 50) {},
            MailPaletteEntry("Settings…", detail: "Brev", shortcutKeycaps: ["⌘", ","]) {},
            MailPaletteEntry("Privacy", detail: "Settings", section: .privacy) {},
        ]
        let host = MailCommandPalette.contentController(theme: theme, entries: entries) { _ in }
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 400)),
            named: "command-palette-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
