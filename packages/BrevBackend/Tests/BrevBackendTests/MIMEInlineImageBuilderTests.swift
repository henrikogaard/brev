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

@testable import BrevBackend
import Foundation
import Testing

@Suite("MIME inline image build")
struct MIMEInlineImageBuilderTests {
    private func build(html: String, attachments: [MIMEMessageAttachment]) -> String {
        let draft = Draft(
            id: "t1",
            to: [Correspondent(email: "b@y.test")],
            subject: "S",
            htmlBody: html
        )
        let from = Correspondent(email: "a@x.test")
        let data = MIMEMessageBuilder(
            draft: draft,
            from: from,
            attachments: attachments,
            boundary: "TEST-BOUNDARY"
        ).build()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("inline attachment emits Content-ID + inline disposition inside multipart/related")
    func inlineEmitsRelated() {
        let inline = MIMEMessageAttachment(
            id: "i1", filename: "p.png", mimeType: "image/png",
            data: Data([0x89, 0x50]), isInline: true, contentID: "img1@brev"
        )
        let mime = build(html: "<p><img src=\"cid:img1@brev\"></p>", attachments: [inline])
        #expect(mime.contains("multipart/related"))
        #expect(mime.contains("Content-ID: <img1@brev>"))
        #expect(mime.contains("Content-Disposition: inline"))
        // text/plain alternative still present
        #expect(mime.contains("text/plain"))
    }

    @Test("regular attachment stays attachment disposition, no related")
    func regularStaysAttachment() {
        let file = MIMEMessageAttachment(
            id: "a1", filename: "d.pdf", mimeType: "application/pdf",
            data: Data([0x25, 0x50]), isInline: false, contentID: nil
        )
        let mime = build(html: "<p>hi</p>", attachments: [file])
        #expect(mime.contains("Content-Disposition: attachment"))
        #expect(!mime.contains("multipart/related"))
    }

    @Test("inline + regular: related nested in alternative, attachment in mixed")
    func mixedTree() {
        let inline = MIMEMessageAttachment(id: "i", filename: "p.png", mimeType: "image/png",
                                           data: Data([1]), isInline: true, contentID: "c@brev")
        let file = MIMEMessageAttachment(id: "a", filename: "d.pdf", mimeType: "application/pdf",
                                         data: Data([2]), isInline: false, contentID: nil)
        let mime = build(html: "<p><img src=\"cid:c@brev\"></p>", attachments: [inline, file])
        #expect(mime.contains("multipart/mixed"))
        #expect(mime.contains("multipart/alternative"))
        #expect(mime.contains("multipart/related"))
        #expect(mime.contains("Content-ID: <c@brev>"))
        #expect(mime.contains("Content-Disposition: attachment"))
    }

    @Test("inline-only draft with attachmentIDs populated omits empty multipart/mixed wrapper")
    func inlineOnlyWithDraftAttachmentIDsOmitsMixed() {
        let webpBytes = Data("RIFF\u{14}\0\0\0WEBPVP8 ".utf8)
        let inline = MIMEMessageAttachment(
            id: "inline-1",
            filename: "photo.webp",
            mimeType: "image/webp",
            data: webpBytes,
            isInline: true,
            contentID: "webp1@brev.inline"
        )
        let draft = Draft(
            id: "t-inline-only",
            to: [Correspondent(email: "b@y.test")],
            subject: "Inline WebP",
            htmlBody: "<p><img src=\"cid:webp1@brev.inline\"></p>",
            attachmentIDs: ["inline-1"]
        )
        let data = MIMEMessageBuilder(
            draft: draft,
            from: Correspondent(email: "a@x.test"),
            attachments: [inline],
            boundary: "INLINE-ONLY-BOUNDARY"
        ).build()
        let mime = String(decoding: data, as: UTF8.self)
        #expect(!mime.contains("multipart/mixed"))
        #expect(mime.contains("multipart/alternative"))
        #expect(mime.contains("multipart/related; type=\"text/html\""))
        #expect(mime.contains("Content-Type: image/webp"))
        #expect(mime.contains("Content-ID: <webp1@brev.inline>"))
        #expect(mime.contains("Content-Disposition: inline"))
    }

    @Test("MockBackend preserves isInline and contentID across stage, save, and localDraftAttachments")
    func mockBackendInlineStagingPreservesMetadata() async throws {
        let backend = MockBackend()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let draftID = "inline-mock-draft"
        let inlineID = try await backend.stageInlineAttachment(
            draftID: draftID,
            contentID: "shot1@brev.inline",
            filename: "image.png",
            mimeType: "image/png",
            data: png
        )
        let saved = try await backend.save(draft: Draft(
            id: draftID,
            to: [Correspondent(email: "b@y.test")],
            subject: "With inline image",
            htmlBody: "<img src=\"cid:shot1@brev.inline\">",
            attachmentIDs: [inlineID]
        ))
        let service = try #require(backend.extensionService(LocalDraftAttachmentProviding.self))
        let restored = try await service.localDraftAttachments(for: saved)
        #expect(restored.count == 1)
        #expect(restored.first?.id == inlineID)
        #expect(restored.first?.isInline == true)
        #expect(restored.first?.contentID == "shot1@brev.inline")
        #expect(restored.first?.mimeType == "image/png")
        #expect(restored.first?.data == png)
    }
}
