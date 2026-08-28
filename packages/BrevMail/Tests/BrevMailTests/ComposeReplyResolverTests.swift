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
import BrevMail
import Foundation
import Testing

@Suite("ComposeReplyResolver")
struct ComposeReplyResolverTests {
    @Test("sender reply targets only the original sender")
    func senderReplyTargetsOnlySender() {
        let header = Self.makeHeader()

        let recipients = ComposeReplyResolver.recipients(
            for: header,
            mode: .sender,
            accountEmail: "henrik@example.org"
        )

        #expect(recipients == ["alex@example.org"])
    }

    @Test("sender reply prefers Reply-To over From")
    func senderReplyPrefersReplyToOverFrom() {
        let header = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "List Sender", email: "bounce@example.org"),
            replyTo: [Correspondent(name: "List Replies", email: "replies@example.org")],
            subject: "Hello",
            snippet: "Hello",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )

        let recipients = ComposeReplyResolver.recipients(
            for: header,
            mode: .sender,
            accountEmail: "henrik@example.org"
        )

        #expect(recipients == ["replies@example.org"])
    }

    @Test("reply all includes sender to and cc while excluding current account")
    func replyAllIncludesSenderToAndCcExcludingAccount() {
        let header = Self.makeHeader()

        let recipients = ComposeReplyResolver.recipients(
            for: header,
            mode: .all,
            accountEmail: "henrik@example.org"
        )

        #expect(recipients == [
            "alex@example.org",
            "maja@example.org",
            "taylor@example.org"
        ])
    }

    @Test("reply all deduplicates case-insensitively")
    func replyAllDeduplicatesCaseInsensitively() {
        let header = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "Alex@Example.org"),
            to: [
                Correspondent(name: "Henrik", email: "henrik@example.org"),
                Correspondent(name: "Alex", email: "alex@example.org")
            ],
            cc: [Correspondent(name: "Maja", email: "MAJA@example.org")],
            subject: "Hello",
            snippet: "Hello",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )

        let recipients = ComposeReplyResolver.recipients(
            for: header,
            mode: .all,
            accountEmail: "HENRIK@example.org"
        )

        #expect(recipients == ["Alex@Example.org", "MAJA@example.org"])
    }

    private static func makeHeader() -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            to: [
                Correspondent(name: "Henrik", email: "henrik@example.org"),
                Correspondent(name: "Maja", email: "maja@example.org")
            ],
            cc: [Correspondent(name: "Taylor", email: "taylor@example.org")],
            subject: "Hello",
            snippet: "Hello",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }
}
