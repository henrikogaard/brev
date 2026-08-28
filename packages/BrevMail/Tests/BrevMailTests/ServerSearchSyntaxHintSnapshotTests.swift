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

@Suite("Server search syntax hint snapshots")
@MainActor
struct ServerSearchSyntaxHintSnapshotTests {
    @Test("native search syntax hint renders compactly")
    func nativeSearchSyntaxHintRendersCompactly() throws {
        let description = ServerSearchSyntaxDescription(
            identifier: "gmail-q",
            displayName: "Gmail search",
            summary: "Use Gmail operators such as from:, label:, and is:unread.",
            examples: [
                ServerSearchSyntaxExample(
                    query: "from:alice@example.com",
                    explanation: "Messages from Alice."
                ),
                ServerSearchSyntaxExample(
                    query: "has:attachment",
                    explanation: "Messages with attachments."
                ),
            ]
        )
        let theme = BrevTheme.brevPaper
        let view = ServerSearchSyntaxHint(description: description)
            .frame(width: 32, height: 32)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 32, height: 32)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 32, height: 32)),
            named: "native-search-syntax-hint",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
