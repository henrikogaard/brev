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

@Suite("MessageEventDraftBuilder")
struct MessageEventDraftBuilderTests {
    private func header(
        subject: String = "Project sync",
        from: Correspondent = Correspondent(name: "Bob", email: "bob@example.org"),
        to: [Correspondent] = [Correspondent(name: nil, email: "team@example.org")],
        cc: [Correspondent] = []
    ) -> MessageHeader {
        MessageHeader(
            id: "INBOX:1",
            threadID: "t1",
            folderID: "INBOX",
            from: from,
            to: to,
            cc: cc,
            subject: subject,
            snippet: "let's sync",
            date: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    @Test("title is the subject, with a fallback when empty")
    func titleFromSubject() {
        let ref = Date(timeIntervalSince1970: 2_000_000)
        let draft = MessageEventDraftBuilder.draft(for: header(), accountID: "a", referenceDate: ref)
        #expect(draft?.title == "Project sync")
        let blank = MessageEventDraftBuilder.draft(for: header(subject: "  "), accountID: "a", referenceDate: ref)
        #expect(blank?.title == "Meeting about email from Bob")
    }

    @Test("attendees are the deduplicated sender + recipients")
    func attendeesFromSenderAndRecipients() {
        let draft = MessageEventDraftBuilder.draft(
            for: header(
                from: Correspondent(name: "Bob", email: "bob@example.org"),
                to: [Correspondent(name: nil, email: "team@example.org")],
                cc: [Correspondent(name: nil, email: "BOB@example.org")] // dup of from, different case
            ),
            accountID: "a",
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        #expect(draft?.attendees == ["bob@example.org", "team@example.org"])
    }

    @Test("defaults to a one-hour event starting at the reference date")
    func defaultsToOneHourEvent() {
        let ref = Date(timeIntervalSince1970: 5_000_000)
        let draft = MessageEventDraftBuilder.draft(for: header(), accountID: "a", referenceDate: ref)
        #expect(draft?.startDate == ref)
        #expect(draft?.endDate == ref.addingTimeInterval(3600))
        #expect(draft?.isCreateEnabled == true)
    }

    @Test("notes carry the attendees and the Brev deep link")
    func notesCarryAttendeesAndLink() throws {
        let draft = try #require(
            MessageEventDraftBuilder.draft(for: header(), accountID: "acct-1", referenceDate: Date(timeIntervalSince1970: 0))
        )
        #expect(draft.notes.contains("Attendees: bob@example.org, team@example.org"))
        #expect(draft.notes.contains("brev://message?accountID=acct-1"))
    }
}
