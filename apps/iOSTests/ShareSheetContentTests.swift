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

import Foundation
import Testing

@Suite("ShareSheetContent")
struct ShareSheetContentTests {
    private func resolve(
        text: String? = nil,
        urls: [URL] = [],
        attachments: [URL] = [],
        unsupported: Int = 0,
        error: String? = nil,
        fits: Bool = true
    ) -> ShareSheetContent {
        ShareSheetContent.resolve(
            text: text,
            urls: urls,
            attachmentURLs: attachments,
            unsupportedCount: unsupported,
            extractionError: error,
            canHandoffText: { _ in fits }
        )
    }

    @Test("starts in a loading state that cannot be opened")
    func loadingCannotOpen() {
        #expect(ShareSheetContent.loading.isLoading)
        #expect(!ShareSheetContent.loading.canOpen)
    }

    @Test("a shared URL lists the address and enables Open Brev")
    func urlEnablesOpen() throws {
        let content = try resolve(urls: [#require(URL(string: "https://example.org/a"))])
        #expect(!content.isLoading)
        #expect(content.urls == ["https://example.org/a"])
        #expect(content.canOpen)
        #expect(content.message == nil)
    }

    @Test("attachments list their file names")
    func attachmentsListNames() {
        let content = resolve(attachments: [URL(fileURLWithPath: "/tmp/ShareHandoff/x/report.pdf")])
        #expect(content.attachmentNames == ["report.pdf"])
        #expect(content.canOpen)
    }

    @Test("nothing shared explains there is no content and stays disabled")
    func emptyShareIsDisabled() {
        let content = resolve()
        #expect(content.message == "No content to share")
        #expect(!content.canOpen)
    }

    @Test("only unsupported items explain the type is not supported")
    func unsupportedOnly() {
        let content = resolve(unsupported: 2)
        #expect(content.message == "This content type is not supported yet.")
        #expect(!content.canOpen)
    }

    @Test("oversized text is dropped but other items still open")
    func oversizedTextIsDropped() throws {
        let content = try resolve(
            text: "very long",
            urls: [#require(URL(string: "https://example.org"))],
            fits: false
        )
        #expect(content.text == nil)
        #expect(content.canOpen)
        #expect(content.notes == ["Shared text is too large to include and was left out."])
    }

    @Test("oversized text alone leaves nothing to open and says why")
    func oversizedTextAlone() {
        let content = resolve(text: "very long", fits: false)
        #expect(content.message == "Shared text is too large to include and was left out.")
        #expect(!content.canOpen)
    }

    @Test("a storage error still opens text and URLs but not attachments")
    func storageErrorKeepsTextOpenable() {
        let withText = resolve(text: "hello", error: "storage")
        #expect(withText.message == "storage")
        #expect(withText.canOpen)

        let withoutText = resolve(error: "storage")
        #expect(!withoutText.canOpen)
    }

    @Test("skipped items are noted next to the shared ones")
    func unsupportedNoteAccompaniesContent() {
        let content = resolve(text: "hello", unsupported: 1)
        #expect(content.canOpen)
        #expect(content.notes.count == 1)
    }
}
