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
}
