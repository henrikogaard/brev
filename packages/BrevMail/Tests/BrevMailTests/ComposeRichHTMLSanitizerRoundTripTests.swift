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
import Foundation
import Testing

@Suite("Rich HTML sanitizer round-trip")
struct ComposeRichHTMLSanitizerRoundTripTests {
    @Test("link, lists, and cid image survive sanitization")
    func survives() {
        let html = "<p><a href=\"https://x.test\">site</a></p>"
            + "<ul><li>one</li></ul><ol><li>a</li></ol>"
            + "<p><img src=\"cid:c@brev\"></p>"
        let out = ComposeHTMLBodyPolicy.richHTML(fromEditorHTML: html)
        #expect(out.contains("<a href=\"https://x.test\">"))
        #expect(out.contains("<ul><li>one</li></ul>") || (out.contains("<ul>") && out.contains("<li>one</li>")))
        #expect(out.contains("<ol>"))
        #expect(out.contains("cid:c@brev"))
    }

    @Test("remote image and script are stripped")
    func stripsUnsafe() {
        let out = ComposeHTMLBodyPolicy.richHTML(fromEditorHTML:
            "<img src=\"https://evil.test/p.png\"><script>x()</script><p>ok</p>")
        #expect(!out.contains("https://evil.test"))
        #expect(!out.lowercased().contains("<script"))
        #expect(out.contains("ok"))
    }
}
