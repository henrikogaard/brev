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
import Foundation
import Testing

@Suite("MessageReadReceiptDraftBuilder")
struct MessageReadReceiptDraftBuilderTests {
    @Test("builds an MDN draft addressed to the requested notification target")
    func buildsMDNDraft() {
        let header = MessageHeader(
            id: "INBOX:42",
            threadID: "<original@example.org>",
            folderID: "INBOX",
            from: Correspondent(email: "sender@example.org"),
            subject: "Planning",
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )

        let draft = MessageReadReceiptDraftBuilder.draft(
            for: ReadReceiptRequest(notificationTo: "sender@example.org"),
            header: header,
            accountEmail: "reader@example.com"
        )

        #expect(draft.to == [Correspondent(email: "sender@example.org")])
        #expect(draft.subject == "Read: Planning")
        #expect(draft.readReceiptResponse == ReadReceiptResponse(
            finalRecipient: "reader@example.com",
            originalMessageID: "<original@example.org>"
        ))
        #expect(draft.readReceiptRequest == nil)
    }
}
