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

@Suite("ComposeInlineImageRegistry")
struct ComposeInlineImageRegistryTests {
    @Test("stages allowed image and assigns content id")
    func stages() {
        let r = ComposeInlineImageRegistry()
        var n = 0
        let img = r.stage(data: Data([1, 2]), mimeType: "image/png", makeID: { n += 1; return "id\(n)@brev" })
        #expect(img?.contentID == "id1@brev")
        #expect(img?.filename == "image.png")
        #expect(r.staged.count == 1)
    }

    @Test("rejects disallowed type and oversize")
    func rejects() {
        let r = ComposeInlineImageRegistry()
        #expect(r.stage(data: Data([1]), mimeType: "image/tiff", makeID: { "x" }) == nil)
        let big = Data(count: ComposeInlineImagePolicy.maxBytes + 1)
        #expect(r.stage(data: big, mimeType: "image/png", makeID: { "x" }) == nil)
        #expect(r.staged.isEmpty)
    }

    @Test("reconcile drops images no longer referenced")
    func reconcile() {
        let r = ComposeInlineImageRegistry()
        let a = r.stage(data: Data([1]), mimeType: "image/png", makeID: { "a@brev" })!
        _ = r.stage(data: Data([2]), mimeType: "image/png", makeID: { "b@brev" })
        r.reconcile(keepingContentIDs: [a.contentID])
        #expect(r.staged.map(\.contentID) == ["a@brev"])
    }

    @Test("pasteboard payload prefers png, maps to mime type")
    func pasteboardPayload() {
        let payload = ComposePasteboardImage.imagePayload(
            types: ["public.tiff", "public.png"],
            data: { $0 == "public.png" ? Data([0x89]) : nil }
        )
        #expect(payload?.mimeType == "image/png")
        #expect(payload?.data == Data([0x89]))
    }

    @Test("detects supported image MIME type from transferred data")
    func detectsTransferredImageMIMEType() {
        #expect(ComposeInlineImageData.mimeType(for: Data([0x89, 0x50, 0x4E, 0x47])) == "image/png")
        #expect(ComposeInlineImageData.mimeType(for: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg")
        #expect(ComposeInlineImageData.mimeType(for: Data("GIF89a".utf8)) == "image/gif")
        #expect(ComposeInlineImageData.mimeType(for: Data("not an image".utf8)) == nil)
    }
}
