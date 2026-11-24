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

@Suite("ComposeHTMLPasteSanitizer")
struct ComposeHTMLPasteSanitizerTests {
    @Test("preserves semantic inline formatting, headings, lists, blockquotes, tables, and code")
    func preservesSemanticFormatting() throws {
        let raw = """
        <h1 style="color:#ff0000;font-family:Comic Sans">Release Notes</h1>
        <h2 class="sub">Highlights</h2>
        <h4 id="deep">Minor note</h4>
        <p style="background:yellow;color:#000">
            <b>Bold</b> <i>Italic</i> <u>Under</u> <del>Old</del> <code>let x = 1</code>
            <a href="https://brevmail.eu/docs" target="_blank" onclick="steal()">Docs</a>
            <a href="mailto:hello@brevmail.eu">Email</a>
        </p>
        <ul><li style="color:blue">First</li><li>Second</li></ul>
        <ol><li>Step 1</li><li>Step 2</li></ol>
        <blockquote style="border-left:4px solid red">Quoted line</blockquote>
        <pre class="lang-swift"><code>func greet() {\n    print("hi &lt;world&gt;")\n}</code></pre>
        <table border="1" bgcolor="#fff">
            <thead><tr><th style="width:100px">Item</th><th>Status</th></tr></thead>
            <tbody><tr><td style="color:green">Sync</td><td><strong>Ready</strong></td></tr></tbody>
        </table>
        """

        let clean = try #require(ComposeHTMLPasteSanitizer.sanitize(raw))
        #expect(clean.contains("<h1>Release Notes</h1>"))
        #expect(clean.contains("<h2>Highlights</h2>"))
        #expect(clean.contains("<h3>Minor note</h3>"))
        #expect(clean.contains("<strong>Bold</strong>"))
        #expect(clean.contains("<em>Italic</em>"))
        #expect(clean.contains("<u>Under</u>"))
        #expect(clean.contains("<s>Old</s>"))
        #expect(clean.contains("<code>let x = 1</code>"))
        #expect(clean.contains("<a href=\"https://brevmail.eu/docs\">Docs</a>"))
        #expect(clean.contains("<a href=\"mailto:hello@brevmail.eu\">Email</a>"))
        #expect(clean.contains("<ul><li>First</li><li>Second</li></ul>"))
        #expect(clean.contains("<ol><li>Step 1</li><li>Step 2</li></ol>"))
        #expect(clean.contains("<blockquote>Quoted line</blockquote>"))
        #expect(clean.contains("<pre><code>func greet() {\n    print(&quot;hi &lt;world&gt;&quot;)\n}</code></pre>"))
        #expect(clean
            .contains(
                "<table><thead><tr><th>Item</th><th>Status</th></tr></thead><tbody><tr><td>Sync</td><td><strong>Ready</strong></td></tr></tbody></table>"
            ))

        // No inline colors, backgrounds, classes, or event handlers remain.
        #expect(!clean.contains("style="))
        #expect(!clean.contains("class="))
        #expect(!clean.contains("bgcolor"))
        #expect(!clean.contains("onclick"))
        #expect(!clean.contains("#ff0000"))
        #expect(!clean.contains("yellow"))
    }

    @Test("strips scripts, styles, iframes, objects, embeds, forms, meta, event handlers, and remote images")
    func stripsDangerousAndNoisyMarkup() throws {
        let raw = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>Secret</title><style>body{color:red}</style></head>
        <body onload="evil()">
        <!-- hidden comment -->
        <script>alert("xss")</script>
        <iframe src="https://evil.invalid/frame"></iframe>
        <object data="https://evil.invalid/obj"></object>
        <embed src="https://evil.invalid/emb">
        <form action="https://evil.invalid/phish"><input type="password"><button>Submit</button></form>
        <img src="https://tracker.invalid/open.gif" width="1" height="1">
        <img src="http://tracker.invalid/pixel.png">
        <img src="data:image/svg+xml,<svg onload=alert(1)>">
        <img src="cid:unknown@other">
        <p onmouseover="evil()">Safe <a href="javascript:alert(1)">bad link</a> and <a href="data:text/html,hi">data link</a></p>
        </body></html>
        """

        let clean = try #require(ComposeHTMLPasteSanitizer.sanitize(raw))
        #expect(!clean.lowercased().contains("<script"))
        #expect(!clean.lowercased().contains("alert("))
        #expect(!clean.lowercased().contains("<style"))
        #expect(!clean.lowercased().contains("color:red"))
        #expect(!clean.lowercased().contains("<iframe"))
        #expect(!clean.lowercased().contains("<object"))
        #expect(!clean.lowercased().contains("<embed"))
        #expect(!clean.lowercased().contains("<form"))
        #expect(!clean.lowercased().contains("<input"))
        #expect(!clean.lowercased().contains("<meta"))
        #expect(!clean.lowercased().contains("<img"))
        #expect(!clean.lowercased().contains("tracker.invalid"))
        #expect(!clean.lowercased().contains("javascript:"))
        #expect(!clean.lowercased().contains("data:text/html"))
        #expect(!clean.lowercased().contains("onload"))
        #expect(!clean.lowercased().contains("onmouseover"))
        #expect(!clean.contains("Secret"))
        #expect(!clean.contains("hidden comment"))
        // Safe link text survives unwrapped without its dangerous href.
        #expect(clean.contains("Safe bad link and data link"))
    }

    @Test("extracts semantic bold/italic/underline/strikethrough from span styles while dropping colors")
    func extractsSemanticSpanStylesWithoutColors() throws {
        let raw = """
        <p><span style="color:#111;background-color:#fff;font-weight:700">BoldSpan</span> \
        <span style="font-style:italic;color:navy">ItalicSpan</span> \
        <span style="text-decoration:underline line-through;background:#eee">BothSpan</span></p>
        """
        let clean = try #require(ComposeHTMLPasteSanitizer.sanitize(raw))
        #expect(clean.contains("<strong>BoldSpan</strong>"))
        #expect(clean.contains("<em>ItalicSpan</em>"))
        #expect(clean.contains("<u><s>BothSpan</s></u>"))
        #expect(!clean.contains("style="))
        #expect(!clean.contains("#111"))
        #expect(!clean.contains("navy"))
    }

    @Test("allows only explicitly authorized cid images and rejects oversized inputs")
    func cidAllowlistAndSizeCap() throws {
        let html = "<p><img src=\"cid:known@brev.inline\" alt=\"Chart\"><img src=\"cid:foreign@other\"></p>"
        let external = try #require(ComposeHTMLPasteSanitizer.sanitize(html))
        #expect(!external.contains("<img"))

        let internalPaste = try #require(ComposeHTMLPasteSanitizer.sanitize(html, allowedCIDs: ["known@brev.inline"]))
        #expect(internalPaste.contains("<img src=\"cid:known@brev.inline\" alt=\"Chart\">"))
        #expect(!internalPaste.contains("foreign@other"))

        let oversized = String(repeating: "a", count: ComposeHTMLPasteSanitizer.maxInputBytes + 1)
        #expect(ComposeHTMLPasteSanitizer.sanitize(oversized) == nil)
    }
}
