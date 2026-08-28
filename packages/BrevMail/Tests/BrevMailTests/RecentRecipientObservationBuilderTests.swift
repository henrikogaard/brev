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

@Suite("RecentRecipientObservationBuilder")
struct RecentRecipientObservationBuilderTests {
    @Test("indexes cached correspondents while excluding the owning account")
    func indexesCachedCorrespondentsWhileExcludingOwningAccount() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let header = MessageHeader(
            id: "m1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.org"),
            replyTo: [Correspondent(name: "Ada Replies", email: "reply@example.org")],
            to: [Correspondent(name: "Me", email: "me@example.org")],
            cc: [
                Correspondent(name: "Grace Hopper", email: "grace@example.org"),
                Correspondent(name: "Me at work", email: "me@work.example.org"),
            ],
            bcc: [Correspondent(name: "Lin", email: "lin@example.org")],
            subject: "Hello",
            snippet: "Hello",
            date: date
        )

        let observations = RecentRecipientObservationBuilder.observations(
            from: [header],
            accountID: "account",
            excludingEmails: ["me@example.org", "me@work.example.org"]
        )

        #expect(observations.map(\.email) == [
            "ada@example.org",
            "reply@example.org",
            "grace@example.org",
            "lin@example.org"
        ])
        #expect(observations.allSatisfy { $0.accountID == "account" && $0.date == date })
    }
}
