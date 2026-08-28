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
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Message raw-source sheet snapshots")
@MainActor
struct MessageRawSourceSheetSnapshotTests {
    private static func header() -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Quarterly report",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: false,
            isFlagged: false
        )
    }

    @Test("View Source loading chrome renders")
    func viewSourceLoading() {
        let theme = BrevTheme.brevBuiltIns.first!
        let view = MessageRawSourceSheet(
            header: Self.header(),
            mode: .fullSource,
            loadSource: { try await Task.sleep(nanoseconds: 5_000_000_000); return "" },
            onClose: {}
        )
        .frame(width: 390, height: 600)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)), named: "view-source-loading")
    }
}
#endif
