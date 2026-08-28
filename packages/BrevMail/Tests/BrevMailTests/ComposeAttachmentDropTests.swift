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
import UniformTypeIdentifiers

@Suite("ComposeAttachmentDrop")
struct ComposeAttachmentDropTests {
    @Test("file URL representation wins over image data so the filename is kept")
    func fileURLWinsOverImageData() {
        let source = ComposeAttachmentDrop.source(
            forRegisteredTypeIdentifiers: ["public.png", "public.file-url", "com.apple.finder.node"]
        )
        #expect(source == .fileURL)
    }

    @Test("image-only providers map to the concrete image type")
    func imageOnlyProviderMapsToImageType() {
        let source = ComposeAttachmentDrop.source(
            forRegisteredTypeIdentifiers: ["public.jpeg", "public.utf8-plain-text"]
        )
        #expect(source == .imageData(.jpeg))
    }

    @Test("unsupported providers are filtered out")
    func unsupportedProvidersAreFiltered() {
        #expect(ComposeAttachmentDrop.source(forRegisteredTypeIdentifiers: ["public.utf8-plain-text"]) == nil)
        #expect(ComposeAttachmentDrop.source(forRegisteredTypeIdentifiers: []) == nil)
        #expect(ComposeAttachmentDrop.source(forRegisteredTypeIdentifiers: ["not.a.real.type"]) == nil)
    }

    @Test("loaded file-URL items decode from URL, NSURL, Data, and String forms")
    func fileURLDecodesFromLoadedItemForms() {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        #expect(ComposeAttachmentDrop.fileURL(fromLoadedItem: url) == url)
        #expect(ComposeAttachmentDrop.fileURL(fromLoadedItem: url as NSURL) == url)
        #expect(ComposeAttachmentDrop.fileURL(fromLoadedItem: url.dataRepresentation) == url)
        #expect(ComposeAttachmentDrop.fileURL(fromLoadedItem: url.absoluteString) == url)
        #expect(ComposeAttachmentDrop.fileURL(fromLoadedItem: Data("not a url".utf8)) == nil)
        #expect(ComposeAttachmentDrop.fileURL(fromLoadedItem: URL(string: "https://example.com/a.png")) == nil)
        #expect(ComposeAttachmentDrop.fileURL(fromLoadedItem: nil) == nil)
    }

    @Test("dropped image data gets a filename with the type's extension")
    func imageFilenameUsesTypeExtension() {
        #expect(ComposeAttachmentDrop.imageFilename(for: .png) == "Image.png")
        #expect(ComposeAttachmentDrop.imageFilename(for: .jpeg) == "Image.jpeg")
    }

    @Test("dropped image data is imported through the attachment import path")
    func imageDataImportsAsAttachment() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        let result = await ComposeAttachmentDrop.importDroppedImages(
            [ComposeAttachmentDrop.DroppedImage(data: png, type: .png)],
            existingFilenames: ["Image.png"],
            existingByteCount: 0
        )

        #expect(result.attachments.count == 1)
        #expect(result.attachments.first?.data == png)
        #expect(result.attachments.first?.mimeType == "image/png")
        // The name is de-duplicated against attachments already staged.
        #expect(result.attachments.first?.filename != "Image.png")
        #expect(result.attachments.first?.filename.hasSuffix(".png") == true)
        #expect(result.errorMessage == nil)
    }
}
