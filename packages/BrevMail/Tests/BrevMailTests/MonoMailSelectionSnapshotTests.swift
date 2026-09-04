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

@Suite("Default mail selection snapshots")
@MainActor
struct MonoMailSelectionSnapshotTests {
    @Test("selected rows and thread children keep readable metadata",
          arguments: [BrevTheme.brevMonoLight, BrevTheme.brevMonoDark], [true, false])
    func selection(theme: BrevTheme, active: Bool) {
        let header = MessageHeader(id: "same", threadID: "thread", folderID: "inbox",
                                   from: Correspondent(name: "Ingrid Halvorsen", email: "ingrid@example.com"),
                                   subject: "The launch plan is ready for review",
                                   snippet: "The rollback plan and support rota are ready.", date: .distantPast)
        let view = VStack(spacing: 8) {
            MessageListRow(header: header, threadCount: 2, isSelected: true, isChecked: false,
                           isInSelectionMode: false, isPinned: false, isThreadExpanded: true,
                           showAvatar: false, previewLineCount: 1, fontFamily: .system, textSize: .medium,
                           density: .comfortable, showsAbsoluteArrivalTime: false, sourceContext: "Work",
                           isBlockedSender: false, hasFollowUp: false, onActivate: {}, onToggleCheck: {}, onToggleThread: {})
            ThreadInlineChildRow(header: header, isSelected: true, onSelect: {})
        }
        .frame(width: 420, height: 160)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.controlActiveState, active ? .key : .inactive)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 420, height: 160)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 420, height: 160)),
                       named: "\(theme.id)-\(active ? "active" : "inactive")",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}
#endif
