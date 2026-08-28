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

@testable import BrevGmail
import Foundation
import Testing

@Suite("Gmail API models")
struct GmailModelsTests {
    @Test("accepts Gmail pages and history events with omitted optional arrays")
    func acceptsOmittedArrays() throws {
        let page = try JSONDecoder().decode(
            GmailMessagePage.self,
            from: Data("{\"nextPageToken\":\"next\"}".utf8)
        )
        let history = try JSONDecoder().decode(
            GmailHistoryPage.self,
            from: Data("{\"historyId\":\"42\",\"history\":[{\"id\":\"43\"}]}".utf8)
        )

        #expect(page.messages.isEmpty)
        #expect(page.nextPageToken == "next")
        #expect(history.historyID == "42")
        #expect(history.history.first?.messagesAdded.isEmpty == true)
    }

    @Test("decodes account-wide message and thread identity")
    func decodesMessageIdentity() throws {
        let message = try JSONDecoder().decode(
            GmailMessage.self,
            from: Data("{\"id\":\"m1\",\"threadId\":\"t1\",\"labelIds\":[\"INBOX\"]}".utf8)
        )

        #expect(message.id == "m1")
        #expect(message.threadID == "t1")
        #expect(message.labelIDs == ["INBOX"])
    }

    @Test("decodes attachment endpoint responses without filename metadata")
    func decodesAttachmentResponse() throws {
        let attachment = try JSONDecoder().decode(
            GmailAttachment.self,
            from: Data("{\"id\":\"a1\",\"size\":12,\"data\":\"YWJj\"}".utf8)
        )

        #expect(attachment.id == "a1")
        #expect(attachment.filename == nil)
        #expect(attachment.size == 12)
    }

    @Test("decodes Gmail provider attachment IDs separately from stable cache IDs")
    func decodesProviderAttachmentID() throws {
        let body = try JSONDecoder().decode(
            GmailMessageBody.self,
            from: Data("{\"size\":12,\"attachmentId\":\"provider-a1\"}".utf8)
        )

        #expect(body.attachmentID == "provider-a1")
    }
}
