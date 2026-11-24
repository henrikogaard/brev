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

    // MARK: - Helper Harness

    @MainActor
    private final class EditorHarness {
        var text: String
        var html: String?
        var selection: ComposeBodyTextSelection?
        var insertion: ComposeBodyInsertionPoint?
        var rejectedMessage: String?
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
