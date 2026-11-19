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

import BrevBackend
@testable import BrevMail
import Testing

/// Which attachments an expanded thread message lists as cards.
@Suite("Thread message attachment list")
struct ThreadMessageAttachmentListPolicyTests {
    private static func file(
        _ id: String,
        name: String = "file.pdf",
        mimeType: String = "application/pdf",
        isInline: Bool = false,
        contentID: String? = nil,
        resource: String? = "res"
    ) -> BrevBackend.Attachment {
        BrevBackend.Attachment(
            id: id, name: name, mimeType: mimeType, sizeBytes: 1024,
            isInline: isInline, contentID: contentID, resource: resource
        )
    }

    @Test("ordinary attachments are listed in message order")
    func ordinaryListed() {
        let attachments = [Self.file("a", name: "Plan.pdf"), Self.file("b", name: "Photo.jpeg", mimeType: "image/jpeg")]
        #expect(ThreadMessageAttachmentListPolicy.listed(attachments).map(\.id) == ["a", "b"])
    }

    @Test("inline CID images are left to the body")
    func inlineCIDExcluded() {
        let attachments = [
            Self.file("logo", name: "logo.png", mimeType: "image/png", isInline: true, contentID: "logo@x"),
            Self.file("a"),
        ]
        #expect(ThreadMessageAttachmentListPolicy.listed(attachments).map(\.id) == ["a"])
    }

    @Test("an inline part without a content ID is still listed")
    func inlineWithoutCIDListed() {
        let attachments = [
            Self.file("x", isInline: true, contentID: nil),
            Self.file("y", isInline: true, contentID: ""),
        ]
        #expect(ThreadMessageAttachmentListPolicy.listed(attachments).map(\.id) == ["x", "y"])
    }

    @Test("an inline non-image part with a content ID is listed, since the body does not draw it")
    func inlineNonImageListed() {
        let attachments = [
            Self.file("pdf", name: "terms.pdf", mimeType: "application/pdf", isInline: true, contentID: "terms@x"),
        ]
        #expect(ThreadMessageAttachmentListPolicy.listed(attachments).map(\.id) == ["pdf"])
    }

    @Test("the calendar invite is left to the invite card; a second one is listed")
    func inviteExcluded() {
        let attachments = [
            Self.file("ics", name: "invite.ics", mimeType: "text/calendar; method=REQUEST"),
            Self.file("a"),
            Self.file("ics2", name: "other.ics", mimeType: "text/calendar"),
        ]
        #expect(ThreadMessageAttachmentListPolicy.listed(attachments).map(\.id) == ["a", "ics2"])
    }

    @Test("a calendar part with no resource is not an invite card, so it is listed")
    func calendarWithoutResourceListed() {
        let attachments = [Self.file("ics", name: "invite.ics", mimeType: "text/calendar", resource: nil)]
        #expect(ThreadMessageAttachmentListPolicy.listed(attachments).map(\.id) == ["ics"])
    }

    @Test("no attachments lists nothing")
    func empty() {
        #expect(ThreadMessageAttachmentListPolicy.listed([]).isEmpty)
    }
}
