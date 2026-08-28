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

@Suite("MessageHeader Codable")
struct MessageHeaderCodableTests {
    @Test("missing reply-to decodes as an empty list")
    func missingReplyToDecodesAsEmptyList() throws {
        let json = #"""
        {
          "id": "message-1",
          "threadID": "thread-1",
          "folderID": "inbox",
          "from": { "email": "alerts@example.com" },
          "to": [],
          "cc": [],
          "bcc": [],
          "subject": "Notice",
          "snippet": "Read this",
          "date": 1779960600,
          "isRead": false,
          "isFlagged": false,
          "isAnswered": false,
          "isForwarded": false,
          "hasAttachments": false
        }
        """#
        let data = try #require(json.data(using: .utf8))
        let header = try JSONDecoder().decode(MessageHeader.self, from: data)

        #expect(header.replyTo == [])
    }

    @Test("reply-to round trips with message headers")
    func replyToRoundTripsWithMessageHeaders() throws {
        let header = MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Example", email: "alerts@example.com"),
            replyTo: [Correspondent(name: "Billing", email: "billing@payments.example.net")],
            subject: "Notice",
            snippet: "Read this",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )

        let data = try JSONEncoder().encode(header)
        let decoded = try JSONDecoder().decode(MessageHeader.self, from: data)

        #expect(decoded.replyTo == [
            Correspondent(name: "Billing", email: "billing@payments.example.net")
        ])
    }
}
