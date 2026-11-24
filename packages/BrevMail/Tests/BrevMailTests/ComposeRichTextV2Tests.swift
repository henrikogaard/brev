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
import Foundation
import SwiftUI
import Testing

@Suite("Rich HTML compose v2 (inline images, paste, tables, code blocks)")
@MainActor
struct ComposeRichTextV2Tests {
    private static let minimalPNG = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
        0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82
    ])
    private static let minimalWebP = Data("RIFF\u{14}\0\0\0WEBPVP8 ".utf8)

    // MARK: - Inline Images (WebP, caps, preview, save/reopen round-trip)

    @Test("WebP magic bytes, pasteboard mapping, and aggregate inline byte cap are enforced")
    func webpAndAggregateCap() {
        #expect(ComposeInlineImageData.mimeType(for: Self.minimalWebP) == "image/webp")
        #expect(ComposeInlineImageData.mimeType(for: Data()) == nil)

        let payload = ComposePasteboardImage.imagePayload(
            types: ["public.tiff", "org.webmproject.webp"],
            data: { $0 == "org.webmproject.webp" ? Self.minimalWebP : nil }
        )
        #expect(payload?.mimeType == "image/webp")
        #expect(payload?.data == Self.minimalWebP)

        let registry = ComposeInlineImageRegistry()
        let tenMB = Data(count: ComposeInlineImagePolicy.maxBytes)
        #expect(registry.stage(data: tenMB, mimeType: "image/webp", makeID: { "1@brev.inline" })?.filename == "image.webp")
        #expect(registry.stage(data: tenMB, mimeType: "image/png", makeID: { "2@brev.inline" }) != nil)
        // 10 + 10 + 6 = 26 MiB > 25 MiB aggregate cap -> rejected!
        let sixMB = Data(count: 6 * 1024 * 1024)
        #expect(registry.stage(data: sixMB, mimeType: "image/jpeg", makeID: { "3@brev.inline" }) == nil)
        #expect(registry.staged.count == 2)
        // Empty payload rejected.
        #expect(registry.stage(data: Data(), mimeType: "image/png", makeID: { "empty@brev.inline" }) == nil)
    }

    @Test("HTML preview rewrites local cid images to data URIs without touching external URLs")
    func htmlPreviewResolvesLocalCIDImages() {
        let image = ComposeInlineImage(
            contentID: "chart1@brev.inline",
            filename: "image.png",
            mimeType: "image/png",
            data: Self.minimalPNG
        )
        let preview = ComposeHTMLPreviewSource.html(
            richHTML: "<p>Look: <img src=\"cid:chart1@brev.inline\"></p>",
            plainBody: "Look:",
            inlineImages: [image]
        )
        #expect(preview.contains("data:image/png;base64,"))
        #expect(!preview.contains("cid:chart1@brev.inline"))
    }

    @Test("inline cid images round-trip across Draft Save, Reopen, and MIME build")
    func inlineImageDraftRoundTrip() async throws {
        let backend = MockBackend()
        let draftID = UUID().uuidString
        let cid = "inline-photo@brev.inline"
        let inlineAttID = try await backend.stageInlineAttachment(
            draftID: draftID,
            contentID: cid,
            filename: "image.png",
            mimeType: "image/png",
            data: Self.minimalPNG
        )
        let html = "Hello <img src=\"cid:\(cid)\"> world"
        let saved = try await backend.save(draft: Draft(
            id: draftID,
            to: [Correspondent(email: "ada@example.invalid")],
            subject: "Inline image",
            htmlBody: html,
            attachmentIDs: [inlineAttID]
        ))

        let folder = try #require(await backend.folders().first { $0.role == .drafts })
        let header = try #require(await backend.messages(in: folder, pageToken: nil).0.first { $0.id == saved.remoteID })
        let resolved = try await ComposeDraftRestoration.resolve(header: header, backend: backend, sourceID: nil)
        #expect(ComposeDraftRestoration.pendingAttachments(from: resolved.attachments).isEmpty)
        #expect(ComposeDraftRestoration.inlineAttachments(from: resolved.attachments).count == 1)

        let body = try await ComposeDraftBodyRestoration.prepare(
            draft: resolved.draft,
            attachments: resolved.attachments,
            format: .richTextHTML
        )
        #expect(body.initialEditorHTML == html)
        #expect(body.originalHTML == html)
        #expect(ComposeRichTextHTMLSerializer.html(from: body.attributedText) == html)

        // Plain-text mode still refuses inline image drafts.
        await #expect(throws: (any Error).self) {
            _ = try await ComposeDraftBodyRestoration.prepare(
                draft: resolved.draft,
                attachments: resolved.attachments,
                format: .plainText
            )
        }

        // Verify MIME build with restored inline attachment emits multipart/related without empty multipart/mixed.
        let mimeData = MIMEMessageBuilder(
            draft: resolved.draft,
            from: Correspondent(email: "henrik@example.invalid"),
            attachments: resolved.attachments,
            boundary: "ROUNDTRIP-BOUNDARY"
        ).build()
        let mime = String(decoding: mimeData, as: UTF8.self)
        #expect(!mime.contains("multipart/mixed"))
        #expect(mime.contains("multipart/alternative"))
        #expect(mime.contains("multipart/related; type=\"text/html\""))
        #expect(mime.contains("Content-ID: <\(cid)>"))
        #expect(mime.contains("Content-Disposition: inline"))
    }

    // MARK: - Tables, Code Blocks, Inline Code, Headings, Strikethrough

    @Test("semantic tables, code blocks, inline code, headings, and strikethrough round-trip losslessly")
    func richElementsRoundTrip() async throws {
        let html = """
        <h1>Roadmap</h1>\
        <h2>Status</h2>\
        <h3>Details</h3>\
        Use <code>git status</code> and <s>old flow</s>.\
        <pre><code>let x = 1 &lt; 2\nprint(x)</code></pre>\
        <table><thead><tr><th>Task</th><th>Owner</th></tr></thead>\
        <tbody><tr><td>Tables</td><td><strong>Henrik</strong></td></tr>\
        <tr><td>Code</td><td><code>BrevMail</code></td></tr></tbody></table>
        """
        let draft = Draft(id: "v2-rich", subject: "Rich v2", htmlBody: html)
        let restored = try await ComposeDraftBodyRestoration.prepare(draft: draft, format: .richTextHTML)

        #expect(restored.originalHTML == html)
        #expect(restored.initialEditorHTML == html)
        #expect(ComposeRichTextHTMLSerializer.html(from: restored.attributedText) == html)

        // Plain-text mode still refuses tables, code blocks, headings, inline code, and strikethrough.
        for richFragment in [
            "<h1>Heading</h1>",
            "<s>Struck</s>",
            "<code>inline()</code>",
            "<pre><code>block()</code></pre>",
            "<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>"
        ] {
            await #expect(throws: (any Error).self) {
                _ = try await ComposeDraftBodyRestoration.prepare(
                    draft: Draft(id: "plain-refuse", htmlBody: richFragment),
                    format: .plainText
                )
            }
        }
    }

    @Test("tables, code blocks, and inline images reopen cleanly alongside PR #350 preserved quote tails")
    func richTopWithPreservedQuoteTail() async throws {
        let cid = "diagram@brev.inline"
        let inlineAttachment = MIMEMessageAttachment(
            id: "att-inline-1",
            filename: "diagram.png",
            mimeType: "image/png",
            data: Self.minimalPNG,
            isInline: true,
            contentID: cid
        )
        let quoteTail = """
        <div class="gmail_quote"><div class="gmail_attr">On Mon, Ada wrote:<br></div>\
        <blockquote class="gmail_quote" style="border-left:1px solid #ccc">Nested <blockquote>thread</blockquote></blockquote></div>
        """
        let topHTML = """
        <h2>Summary</h2>\
        <img src="cid:\(cid)">\
        <pre><code>swift test</code></pre>\
        <table><thead><tr><th>Area</th><th>State</th></tr></thead><tbody><tr><td>Compose</td><td>Done</td></tr></tbody></table>
        """
        let fullHTML = "\(topHTML)<br><br>\(quoteTail)"

        let draft = Draft(
            id: "rich-plus-quote",
            inReplyToMessageID: "<orig@example.invalid>",
            htmlBody: fullHTML,
            attachmentIDs: [inlineAttachment.id]
        )
        #expect(ComposeDraftRestoration.validationError(draft: draft, attachments: [inlineAttachment]) == nil)

        let restored = try await ComposeDraftBodyRestoration.prepare(
            draft: draft,
            attachments: [inlineAttachment],
            format: .richTextHTML
        )
        #expect(restored.originalHTML == fullHTML)
        #expect(restored.initialEditorHTML == topHTML)
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(restored.quoteSeparatorHTML == "<br><br>")

        let unedited = restored.htmlBodyForSave(
            currentBodyText: restored.attributedText.string,
            currentBodyHTML: restored.initialEditorHTML,
            editedTopHTML: restored.initialEditorHTML
        )
        #expect(unedited == fullHTML)
    }

    @Test("Format menu commands insert tables, code blocks, inline code, headings, and strikethrough in macOS editor")
    func editorFormatCommandsWork() throws {
        let harness = EditorHarness(text: "Title\nBody word\nlet a = 1")
        let editor = try harness.mount()
        let ns = editor.string as NSString

        // Heading 1
        editor.setSelectedRange(ns.range(of: "Title"))
        try harness.perform(.heading1, in: editor)
        #expect(harness.html?.contains("<h1>Title</h1>") == true)

        // Strikethrough + inline code on "word"
        editor.setSelectedRange((editor.string as NSString).range(of: "word"))
        try harness.perform(.strikethrough, in: editor)
        try harness.perform(.inlineCode, in: editor)
        #expect(harness.html?.contains("<s><code>word</code></s>") == true)

        // Code block on "let a = 1"
        editor.setSelectedRange((editor.string as NSString).range(of: "let a = 1"))
        try harness.perform(.codeBlock, in: editor)
        #expect(harness.html?.contains("<pre><code>let a = 1</code></pre>") == true)

        // Insert table at end
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        try harness.perform(.insertTable, in: editor)
        #expect(harness.html?.contains("<table><thead><tr><th>") == true)
        #expect(harness.html?.contains("<tbody><tr><td>") == true)
    }

    @Test("pasting messy HTML into the macOS rich editor sanitizes scripts/colors and preserves tables & code")
    func sanitizedHTMLPasteInEditor() throws {
        let harness = EditorHarness(text: "")
        let editor = try harness.mount()

        let dirtyHTML = """
        <style>p{color:red}</style><script>alert(1)</script>
        <p style="color:#ff0000"><b>Hello</b> <code>world</code> <a href="javascript:alert(1)">bad</a></p>
        <img src="https://tracker.invalid/px.gif">
        <table><thead><tr><th>K</th></tr></thead><tbody><tr><td>V</td></tr></tbody></table>
        """
        let inserted = editor.brevInsertSanitizedHTML(dirtyHTML)
        harness.flush.performFlush()

        #expect(inserted)
        let html = try #require(harness.html)
        #expect(html.contains("<strong>Hello</strong>"))
        #expect(html.contains("<code>world</code>"))
        #expect(html.contains("<table><thead><tr><th>K</th></tr></thead><tbody><tr><td>V</td></tr></tbody></table>"))
        #expect(!html.contains("script"))
        #expect(!html.contains("tracker.invalid"))
        #expect(!html.contains("javascript:"))
        #expect(!html.contains("style="))
    }

    @Test("pasting an oversized or unsupported inline image into macOS editor fails closed and reports error")
    func rejectedInlineImageFailsClosed() throws {
        let harness = EditorHarness(text: "Hi")
        let editor = try harness.mount()
        let rejectedBadType = editor.brevInsertImagePayload(data: Data("not an image".utf8), mimeType: "image/svg+xml")
        #expect(!rejectedBadType)
        #expect(harness.rejectedMessage == ComposeInlineImagePolicy.unsupportedFormatMessage)
        #expect(harness.registry.staged.isEmpty)

        let oversized = Data(count: ComposeInlineImagePolicy.maxBytes + 1)
        let rejectedBig = editor.brevInsertImagePayload(data: oversized, mimeType: "image/png")
        #expect(!rejectedBig)
        #expect(harness.rejectedMessage == ComposeInlineImagePolicy.sizeLimitExceededMessage)
        #expect(harness.registry.staged.isEmpty)
    }

    // MARK: - Round-1 Regression Coverage

    @Test("multiline table cells coalesce paragraphs by (row, col) with <br> and round-trip cleanly")
    func multilineTableCellsRoundTrip() async throws {
        let html = """
        <table><thead><tr><th>Item</th><th>Notes</th></tr></thead>\
        <tbody><tr><td>Line 1<br>Line 2</td><td>Single</td></tr></tbody></table>
        """
        let restored = try await ComposeDraftBodyRestoration.prepare(
            draft: Draft(id: "multiline-table", htmlBody: html),
            format: .richTextHTML
        )
        #expect(ComposeRichTextHTMLSerializer.html(from: restored.attributedText) == html)

        // Programmatically append a second paragraph carrying the same (tableID, row, col)
        // to simulate pressing Return inside a table cell.
        let combined = NSMutableAttributedString()
        let meta = ComposeTableCellMetadata(tableID: "t1", row: 0, column: 0, isHeader: false)
        let metaRight = ComposeTableCellMetadata(tableID: "t1", row: 0, column: 1, isHeader: false)
        combined.append(NSAttributedString(string: "First\n", attributes: [ComposeRichTextAttribute.tableCell: meta]))
        combined.append(NSAttributedString(string: "Second\n", attributes: [ComposeRichTextAttribute.tableCell: meta]))
        combined.append(NSAttributedString(string: "Right", attributes: [ComposeRichTextAttribute.tableCell: metaRight]))
        #expect(
            ComposeRichTextHTMLSerializer.html(from: combined)
                == "<table><tbody><tr><td>First<br>Second</td><td>Right</td></tr></tbody></table>"
        )
    }

    @Test("inserting a table or pasting block HTML mid-paragraph splices cleanly while inline paste stays inline")
    func midParagraphBlockSpliceAndInlinePaste() throws {
        // 1. Insert table midway through "Hello world"
        let tableHarness = EditorHarness(text: "Hello world")
        let tableEditor = try tableHarness.mount()
        tableEditor.setSelectedRange(NSRange(location: 6, length: 0))
        try tableHarness.perform(.insertTable, in: tableEditor)
        let tableHTML = try #require(tableHarness.html)
        #expect(tableHTML.hasPrefix("Hello <table>"))
        #expect(tableHTML.hasSuffix("</table>world"))

        // 2. Paste <pre><code> midway through "Hello world"
        let codeHarness = EditorHarness(text: "Hello world")
        let codeEditor = try codeHarness.mount()
        codeEditor.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(codeEditor.brevInsertSanitizedHTML("<pre><code>let x = 1</code></pre>"))
        codeHarness.flush.performFlush()
        let codeHTML = try #require(codeHarness.html)
        #expect(codeHTML == "Hello <pre><code>let x = 1</code></pre>world")

        // 3. Paste <h1> midway through "Hello world"
        let headingHarness = EditorHarness(text: "Hello world")
        let headingEditor = try headingHarness.mount()
        headingEditor.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(headingEditor.brevInsertSanitizedHTML("<h1>Banner</h1>"))
        headingHarness.flush.performFlush()
        let headingHTML = try #require(headingHarness.html)
        #expect(headingHTML == "Hello <h1>Banner</h1>world")

        // 4. Paste inline <strong> midway through "Hello world" stays inline
        let inlineHarness = EditorHarness(text: "Hello world")
        let inlineEditor = try inlineHarness.mount()
        inlineEditor.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(inlineEditor.brevInsertSanitizedHTML("<strong>bold </strong>"))
        inlineHarness.flush.performFlush()
        #expect(inlineHarness.html == "Hello <strong>bold </strong>world")
    }

    @Test("locked reply quote blocks rich formatting commands and block insertions")
    func lockedReplyQuoteBlocksRichCommands() throws {
        let body = "Reply line\n\nOn Mon, Ada wrote:\n> Quoted original"
        let harness = EditorHarness(text: body)
        harness.quoteProtection = ComposeQuoteProtection(marker: "On Mon, Ada wrote:", edge: .bottom)
        let editor = try harness.mount()
        let quoteRange = (editor.string as NSString).range(of: "Quoted original")
        let beforeQuote = try #require(editor.textStorage?.attributedSubstring(from: quoteRange))

        // Select inside the protected quote and try every rich command.
        editor.setSelectedRange(quoteRange)
        for command: ComposeRichTextCommand in [
            .strikethrough, .heading1, .inlineCode, .codeBlock, .insertTable, .bulletedList
        ] {
            try harness.perform(command, in: editor)
        }
        #expect(!editor.brevInsertSanitizedHTML("<p>Injected</p>"))
        #expect(!editor.brevInsertImagePayload(data: Self.minimalPNG, mimeType: "image/png"))

        // Select All (overlapping editable + protected quote) is also refused.
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        for command: ComposeRichTextCommand in [
            .strikethrough, .heading2, .inlineCode, .codeBlock, .insertTable, .numberedList
        ] {
            try harness.perform(command, in: editor)
        }

        #expect(editor.string == body)
        let afterQuote = try #require(editor.textStorage?.attributedSubstring(from: quoteRange))
        #expect(afterQuote.isEqual(to: beforeQuote))
        #expect(harness.registry.staged.isEmpty)
    }

    @Test("deleting an inline image across autosave remains recoverable on Undo while active drafts drop it")
    func undoableInlineImageAcrossAutosave() throws {
        let registry = ComposeInlineImageRegistry()
        let cid = "undo-photo@brev.inline"
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "default")
        let stagedImage = try #require(registry.stage(
            data: Self.minimalPNG,
            mimeType: "image/png",
            makeID: { cid }
        ))
        let stagedAttachments: [String: ComposeStagedInlineAttachment] = [
            cid: ComposeStagedInlineAttachment(attachmentID: "att-1", sourceID: sourceID)
        ]

        // 1. User deletes the image from the editor, then autosave runs with reconcileRegistry: false.
        let deletedBodyHTML = "<p>No image right now</p>"
        let imagesOnAutosave = ComposeDraftBuilder.inlineAttachments(
            fromRegistry: registry,
            draftID: "draft-1",
            bodyHTML: deletedBodyHTML,
            reconcileRegistry: false
        )
        #expect(imagesOnAutosave.isEmpty)
        #expect(registry.staged == [stagedImage])
        let activeAfterDelete = ComposeInlineImageRegistry.contentIDs(inHTML: deletedBodyHTML)
        #expect(
            ComposeAttachmentUploadState.inlineAttachmentIDs(
                from: stagedAttachments,
                for: sourceID,
                activeContentIDs: activeAfterDelete
            ).isEmpty
        )

        // 2. User presses Undo -> cid returns in bodyHTML -> next save/send recovers the image & attachment ID!
        let restoredBodyHTML = "<p>Back again <img src=\"cid:\(cid)\"></p>"
        let imagesAfterUndo = ComposeDraftBuilder.inlineAttachments(
            fromRegistry: registry,
            draftID: "draft-1",
            bodyHTML: restoredBodyHTML,
            reconcileRegistry: false
        )
        #expect(imagesAfterUndo.count == 1)
        #expect(imagesAfterUndo[0].contentID == cid)
        let activeAfterUndo = ComposeInlineImageRegistry.contentIDs(inHTML: restoredBodyHTML)
        #expect(
            ComposeAttachmentUploadState.inlineAttachmentIDs(
                from: stagedAttachments,
                for: sourceID,
                activeContentIDs: activeAfterUndo
            ) == ["att-1"]
        )

        // 3. Aggregate 25 MiB cap counts active images only, evicting unreferenced undo images only if needed.
        let capRegistry = ComposeInlineImageRegistry()
        let tenMB = Data(count: ComposeInlineImagePolicy.maxBytes)
        #expect(capRegistry.stage(data: tenMB, mimeType: "image/png", activeContentIDs: [], makeID: { "a@brev.inline" }) != nil)
        #expect(capRegistry.stage(
            data: tenMB,
            mimeType: "image/png",
            activeContentIDs: ["a@brev.inline"],
            makeID: { "b@brev.inline" }
        ) != nil)
        // Pretend "a@brev.inline" was deleted from the editor (only "b@brev.inline" is active).
        #expect(capRegistry.stage(
            data: tenMB,
            mimeType: "image/png",
            activeContentIDs: ["b@brev.inline"],
            makeID: { "c@brev.inline" }
        ) != nil)
        #expect(Set(capRegistry.staged.map(\.contentID)) == ["b@brev.inline", "c@brev.inline"])
    }

    @Test("trailing empty lines in <pre><code> blocks round-trip losslessly")
    func codeBlockTrailingEmptyLinesRoundTrip() async throws {
        for html in [
            "<pre><code>print(1)\n</code></pre>",
            "<pre><code>print(1)\n\n</code></pre>",
            "<pre><code>&amp;#60; Caf&eacute; &Aring;lesund</code></pre>"
        ] {
            let restored = try await ComposeDraftBodyRestoration.prepare(
                draft: Draft(id: "code-trailing", htmlBody: html),
                format: .richTextHTML
            )
            let roundTripped = ComposeRichTextHTMLSerializer.html(from: restored.attributedText)
            if html.contains("&amp;#60;") {
                #expect(restored.attributedText.string == "&#60; Café Ålesund")
                #expect(roundTripped == "<pre><code>&amp;#60; Café Ålesund</code></pre>")
            } else {
                #expect(roundTripped == html)
            }
        }
    }

    @Test("toggling Code Block on an inline-image paragraph preserves the image and serializer never emits U+FFFC")
    func codeBlockPreservesInlineImages() throws {
        let harness = EditorHarness(text: "")
        let editor = try harness.mount()
        #expect(editor.brevInsertImagePayload(data: Self.minimalPNG, mimeType: "image/png"))
        harness.flush.performFlush()
        let beforeHTML = try #require(harness.html)
        #expect(beforeHTML.contains("<img src=\"cid:"))

        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        try harness.perform(.codeBlock, in: editor)
        #expect(harness.html == beforeHTML)
        #expect(harness.html?.contains("\u{FFFC}") == false)

        // Serializer defense-in-depth: even if an attributed string carries both codeBlockID
        // and an inline image attachment, the serializer breaks out the <img> and never emits U+FFFC.
        let attachment = NSTextAttachment()
        let mixed = NSMutableAttributedString(string: "let x = 1\n", attributes: [
            ComposeRichTextAttribute.codeBlockID: "cb-1"
        ])
        let img = NSMutableAttributedString(attachment: attachment)
        img.addAttributes([
            ComposeInlineImageAttribute.contentID: "safe@brev.inline",
            ComposeRichTextAttribute.codeBlockID: "cb-1"
        ], range: NSRange(location: 0, length: img.length))
        mixed.append(img)
        let serialized = ComposeRichTextHTMLSerializer.html(from: mixed)
        #expect(serialized.contains("<pre><code>let x = 1</code></pre>"))
        #expect(serialized.contains("<img src=\"cid:safe@brev.inline\">"))
        #expect(!serialized.contains("\u{FFFC}"))
    }

    @Test("caret on trailing empty line updates typingAttributes for Heading and Code Block without mutating previous line")
    func caretOnTrailingEmptyLineTargetsNewLine() throws {
        // Heading on trailing empty line
        let headingHarness = EditorHarness(text: "Hello\n")
        let headingEditor = try headingHarness.mount()
        headingEditor.setSelectedRange(NSRange(location: 6, length: 0))
        try headingHarness.perform(.heading1, in: headingEditor)
        #expect(headingEditor.typingAttributes[ComposeRichTextAttribute.headingLevel] as? Int == 1)
        #expect(headingHarness.html?.contains("<h1>Hello</h1>") == false)
        headingEditor.insertText("Title", replacementRange: headingEditor.selectedRange())
        headingHarness.flush.performFlush()
        #expect(headingHarness.html == "Hello<h1>Title</h1>")

        // Code block on trailing empty line
        let codeHarness = EditorHarness(text: "Hello\n")
        let codeEditor = try codeHarness.mount()
        codeEditor.setSelectedRange(NSRange(location: 6, length: 0))
        try codeHarness.perform(.codeBlock, in: codeEditor)
        #expect(codeEditor.typingAttributes[ComposeRichTextAttribute.codeBlockID] != nil)
        #expect(codeHarness.html?.contains("<pre><code>Hello") == false)
        codeEditor.insertText("let y = 2", replacementRange: codeEditor.selectedRange())
        codeHarness.flush.performFlush()
        #expect(codeHarness.html == "Hello<pre><code>let y = 2</code></pre>")

        // Caret at end of non-empty final line without trailing newline still toggles that line
        let sameLineHarness = EditorHarness(text: "Hello")
        let sameLineEditor = try sameLineHarness.mount()
        sameLineEditor.setSelectedRange(NSRange(location: 5, length: 0))
        try sameLineHarness.perform(.heading2, in: sameLineEditor)
        #expect(sameLineHarness.html == "<h2>Hello</h2>")
    }

    // MARK: - Helper Harness

    @MainActor
    private final class EditorHarness {
        var text: String
        var html: String?
        var selection: ComposeBodyTextSelection?
        var insertion: ComposeBodyInsertionPoint?
        var rejectedMessage: String?
        var quoteProtection: ComposeQuoteProtection?
        let registry = ComposeInlineImageRegistry()
        let flush = ComposeHTMLPublicationFlushBox()
        let targetBox = ComposeMacRichTextTargetBox()
        private var host: NSHostingView<ComposeBodyEditor>?

        init(text: String) {
            self.text = text
        }

        func mount() throws -> ComposeRichTextView {
            let host = NSHostingView(rootView: ComposeBodyEditor(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                richHTML: Binding(get: { self.html }, set: { self.html = $0 }),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 }),
                insertionPoint: Binding(get: { self.insertion }, set: { self.insertion = $0 }),
                bodyFormat: .richTextHTML,
                appearance: .light,
                htmlPublicationFlushBox: flush,
                textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: false),
                inlineImageRegistry: registry,
                onInlineImageRejected: { [weak self] message in self?.rejectedMessage = message },
                quoteProtection: quoteProtection,
                macRichTextTargetBox: targetBox
            ))
            host.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
            host.layoutSubtreeIfNeeded()
            self.host = host
            let editor = try #require(Self.editor(in: host))
            flush.performFlush()
            return editor
        }

        func perform(_ command: ComposeRichTextCommand, in editor: ComposeRichTextView) throws {
            try #require(editor.tryToPerform(command.actionSelector, with: nil))
            flush.performFlush()
        }

        private static func editor(in view: NSView) -> ComposeRichTextView? {
            if let editor = view as? ComposeRichTextView { return editor }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
    }
}
#endif
