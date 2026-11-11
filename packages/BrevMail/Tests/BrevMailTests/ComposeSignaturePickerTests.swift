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
import SwiftUI
import Testing

/// The signature picker stays reachable on a new message, whose header
/// starts folded into one "From … Cc/Bcc" row.
@Suite("Compose signature picker")
@MainActor
struct ComposeSignaturePickerTests {
    @Test("a new message shows the signature picker while the header is folded")
    func pickerInFoldedHeader() throws {
        let backend = MockBackend()
        let context = ComposeSignatureContext(
            selectedSignatureID: "sig-work",
            options: [
                ComposeSignatureOption(id: "sig-work", title: "Work", body: "Henrik\nBrev"),
                ComposeSignatureOption(id: "sig-personal", title: "Personal", body: "Henrik")
            ]
        )
        var mounted: ComposeView?
        var view = ComposeView(backend: backend, from: backend.account, signatureContext: context)
        view.inspection = { mounted = $0 }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        host.layoutSubtreeIfNeeded()
        defer { host.rootView = ComposeView(backend: backend, from: backend.account) }
        let compose = try #require(mounted)
        #expect(compose.isOptionalFieldsCollapsed)
        #expect(compose.showsSignaturePickerInFoldedRow)
    }

    @Test("without signatures the folded row has no picker")
    func noPickerWithoutSignatures() throws {
        let backend = MockBackend()
        var mounted: ComposeView?
        var view = ComposeView(backend: backend, from: backend.account)
        view.inspection = { mounted = $0 }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        host.layoutSubtreeIfNeeded()
        let compose = try #require(mounted)
        #expect(!compose.showsSignaturePickerInFoldedRow)
    }
}
#endif
