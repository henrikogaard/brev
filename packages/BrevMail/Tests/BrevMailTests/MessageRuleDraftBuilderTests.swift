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
@testable import BrevSettings
import Foundation
import Testing

@Suite("MessageRuleDraftBuilder")
struct MessageRuleDraftBuilderTests {
    private func header(name: String?, email: String, subject: String = "Hi") -> MessageHeader {
        MessageHeader(
            id: "INBOX:1",
            threadID: "t1",
            folderID: "INBOX",
            from: Correspondent(name: name, email: email),
            subject: subject,
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("seeds a Sender contains condition from the message sender")
    func seedsSender() {
        let draft = MessageRuleDraftBuilder.draft(for: header(name: "Bob", email: "bob@example.org"))
        #expect(draft.conditionKind == .senderContains)
        #expect(draft.makeRule().conditions == [.senderContains("bob@example.org")])
    }

    @Test("defaults to the safe, non-destructive Mark read action")
    func safeDefaultAction() {
        let draft = MessageRuleDraftBuilder.draft(for: header(name: nil, email: "list@example.org"))
        #expect(draft.makeRule().actions == [.markRead])
        #expect(draft.isEnabled)
    }

    @Test("names the rule after the sender display name, falling back to the address")
    func ruleName() {
        #expect(
            MessageRuleDraftBuilder.draft(for: header(name: "Bob Roberts", email: "bob@example.org")).name
                == "Mail from Bob Roberts"
        )
        #expect(
            MessageRuleDraftBuilder.draft(for: header(name: "  ", email: "list@example.org")).name
                == "Mail from list@example.org"
        )
    }
}
