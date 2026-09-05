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

@Suite("Folder export feedback snapshots")
@MainActor
struct MailFolderExportStatusSnapshotTests {
    @Test("settled export feedback shares readable controls in both themes", arguments: [false, true])
    func settledFeedback(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = VStack(spacing: 12) {
            MailFolderExportStatusView(state: .completed(URL(fileURLWithPath: "/tmp/Inbox.mbox"), 120),
                                       sourceTitle: "Inbox · Work", onCancel: {}, onDismiss: {})
            MailFolderExportStatusView(state: .failed("Connection lost. Try again."),
                                       sourceTitle: "Receipts · Private", onCancel: {}, onDismiss: {})
            MailFolderExportStatusView(state: .cancelled,
                                       sourceTitle: "Archive · Work", onCancel: {}, onDismiss: {})
        }
        .padding(16).frame(width: 640, height: 250)
        .background(theme.bgPrimary.color).brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 640, height: 250)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 640, height: 250)),
                       named: dark ? "export-dark" : "export-light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}
#endif
