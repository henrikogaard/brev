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
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for `ComposeView`'s chrome: the desktop toolbar
/// (text Send on the trailing edge) and the header field rows, including
/// the From picker row whose address must align with the plain-text field
/// contents below it. Set `RECORD_SNAPSHOTS=YES` to record or refresh the
/// baselines.
@Suite("ComposeView macOS snapshots")
@MainActor
struct ComposeViewMacOSSnapshotTests {
    @Test("compose chrome renders text Send and an aligned From row", arguments: ["light", "dark"])
    func composeChrome(mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let backend = MockBackend()
        let accountID = backend.account.id
        let senderOptions = [
            ComposeSenderOption(
                sourceID: nil,
                accountID: accountID,
                displayName: "Henrik Øgård",
                email: "henrik@ogard.example",
                subtitle: "Primary"
            ),
            ComposeSenderOption(
                sourceID: nil,
                accountID: accountID,
                displayName: nil,
                email: "henrik@ogard.no",
                subtitle: "Alias"
            ),
        ]
        let view = ComposeView(
            backend: backend,
            from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
            senderOptions: senderOptions
        )
        .frame(width: 700, height: 560)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 700, height: 560)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 700, height: 560)),
            named: "compose-chrome-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
