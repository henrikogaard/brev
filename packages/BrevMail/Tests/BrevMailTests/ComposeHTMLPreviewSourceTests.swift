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

@testable import BrevMail
import Testing

@Suite("ComposeHTMLPreviewSource")
struct ComposeHTMLPreviewSourceTests {
    @Test("prefers non-empty rich HTML over plain body")
    func prefersRichHTML() {
        let html = ComposeHTMLPreviewSource.html(richHTML: "<strong>Hi</strong>", plainBody: "Hi")
        #expect(html == "<strong>Hi</strong>")
    }

    @Test("falls back to escaped plain body when rich HTML missing")
    func fallsBackToPlain() {
        let html = ComposeHTMLPreviewSource.html(richHTML: nil, plainBody: "A < B")
        #expect(html.contains("A &lt; B"))
        #expect(!html.contains("<strong>"))
    }

    @Test("empty rich HTML falls back to plain")
    func emptyRichFallsBack() {
        let html = ComposeHTMLPreviewSource.html(richHTML: "", plainBody: "Plain")
        #expect(html == "Plain" || html.contains("Plain"))
    }

    @Test("dark compose appearance maps to dark rendering mode")
    func renderingModeMapping() {
        #expect(ComposeHTMLPreviewSource.renderingMode(for: .dark) == .dark)
        #expect(ComposeHTMLPreviewSource.renderingMode(for: .light) == .original)
        #expect(ComposeHTMLPreviewSource.renderingMode(for: .system) == .original)
    }
}
