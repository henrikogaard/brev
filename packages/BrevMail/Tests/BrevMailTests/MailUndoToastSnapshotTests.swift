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
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Mail Undo feedback snapshots")
@MainActor
struct MailUndoToastSnapshotTests {
    @Test("failed reversals offer a visible retry in both themes", arguments: [false, true])
    func failure(dark: Bool) async {
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "Archived") { throw UndoSnapshotError.offline })
        _ = await queue.undo()?.value
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = MailUndoToast(queue: queue, isBlocked: false, onUndo: {}, onRetry: {})
            .padding(16)
            .frame(width: 600, height: 120)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 600, height: 120)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 600, height: 120)),
                       named: dark ? "retry-dark" : "retry-light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}

private enum UndoSnapshotError: LocalizedError {
    case offline
    var errorDescription: String? { "The mailbox is offline." }
}
#endif
