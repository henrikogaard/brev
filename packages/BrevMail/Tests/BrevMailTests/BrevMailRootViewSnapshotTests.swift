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

/// Snapshot coverage for `BrevMailRootView` — the top-level mail
/// workspace that composes the sidebar, message list, and reading
/// pane. Locks in the compact (iPhone-width) layout in the default
/// theme so regressions in the root composition are caught.
@Suite("BrevMailRootView snapshots")
@MainActor
struct BrevMailRootViewSnapshotTests {
    @Test("Root view renders compact layout with sidebar and list in default theme")
    func rootViewCompactLayout() {
        let theme = BrevTheme.brevPaper
        let view = BrevMailRootView(
            backend: MockBackend(),
            onChangeTheme: { _ in }
        )
        .frame(width: 390, height: 780)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "root-compact"
        )
    }

    @Test("Root view renders wide layout with sidebar, list, and reading pane in default theme")
    func rootViewWideLayout() {
        let theme = BrevTheme.brevPaper
        let view = BrevMailRootView(
            backend: MockBackend(),
            onChangeTheme: { _ in }
        )
        .frame(width: 960, height: 600)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "root-wide"
        )
    }
}
#endif
