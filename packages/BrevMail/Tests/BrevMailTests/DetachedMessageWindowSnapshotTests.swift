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
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the content surface of a detached message reader.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Detached message window snapshots")
@MainActor
struct DetachedMessageWindowSnapshotTests {
    @Test("detached reader preserves utility surface around message content")
    func detachedReaderContent() {
        let theme = BrevTheme.brevPaper
        let header = MessageHeader(
            id: "inbox:detached-reader",
            threadID: "thread-detached-reader",
            folderID: "inbox",
            from: Correspondent(name: "Avery Kim", email: "avery@example.org"),
            subject: "Project update",
            snippet: "Standalone readers preserve the selected utility surface.",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
        let view = MessageDetailView(
            backend: MockBackend(),
            header: header,
            closeWindow: {}
        )
        .brevMailPaneSurface(.content)
        .background(BrevWindowSurfaceBackground(role: .utility).ignoresSafeArea())
        .brevWindowTranslucency(windowRole: .utility)
        .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 680, height: 560)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 680, height: 560)),
            named: "reader-content",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
