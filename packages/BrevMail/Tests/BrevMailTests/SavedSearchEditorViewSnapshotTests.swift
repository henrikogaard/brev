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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Saved Search editor snapshots")
@MainActor
struct SavedSearchEditorViewSnapshotTests {
    @Test("Create mode renders")
    func create() {
        let theme = BrevTheme.brevBuiltIns.first!
        let view = SavedSearchEditorView(onFinished: {})
            .frame(width: 390, height: 600)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)), named: "create")
    }
}

#elseif os(macOS)
import AppKit
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Smart View editor snapshots")
@MainActor
struct SavedSearchEditorViewSnapshotTests {
    @Test("Create mode exposes common message filters")
    func create() {
        let theme = BrevTheme.brevPaper
        let view = SavedSearchEditorView(onFinished: {})
            .frame(width: 520, height: 560)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 520, height: 560)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 520, height: 560)),
            named: "create-macos",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
