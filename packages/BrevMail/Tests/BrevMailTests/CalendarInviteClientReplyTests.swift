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
import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

@Suite("CalendarInviteClientReply")
struct CalendarInviteClientReplyTests {
    @Test("SMTP-capable accounts can send client-side iMIP replies")
    func smtpCapableAccountsCanSendClientSideIMIPReplies() throws {
        let event = try #require(ICSParser.parseFirstEvent(from: Self.invite))
        let account = BrevAccount(
            id: "account",
            displayName: "Henrik",
            emailAddress: "henrik@example.org",
            backendIdentifier: "imap",
            backendDisplayName: "IMAP"
        )

        let payload = try CalendarInviteClientReplyComposer.compose(
            event: event,
            response: .accepted,
            account: account,
            messageID: "m1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(payload.draft.inReplyToMessageID == "m1")
        #expect(payload.draft.to == [Correspondent(name: "Alex", email: "alex@example.org")])
        #expect(payload.draft.subject == "Accepted: Product review")
        #expect(payload.filename == "product-review-reply.ics")
        #expect(payload.mimeType == "text/calendar; method=REPLY")
        #expect(String(decoding: payload.attachmentData, as: UTF8.self).contains("METHOD:REPLY"))
    }

    @Test("a malicious invite SUMMARY is HTML-escaped in the reply body")
    func maliciousSummaryIsEscapedInReplyBody() throws {
        // The event SUMMARY is attacker-controlled and flows into the reply's
        // htmlBody. A crafted title must be escaped, not rendered as live markup.
        let event = try #require(ICSParser.parseFirstEvent(from: Self.inviteWithMaliciousSummary))
        let account = BrevAccount(
            id: "account",
            displayName: "Henrik",
            emailAddress: "henrik@example.org",
            backendIdentifier: "imap",
            backendDisplayName: "IMAP"
        )

        let payload = try CalendarInviteClientReplyComposer.compose(
            event: event,
            response: .accepted,
            account: account,
            messageID: "m1"
        )

        // The dangerous raw tag must be neutralized: `<`/`>` are escaped so the
        // markup becomes inert text. (The literal substring `onerror=` survives
        // because `=` is not HTML-special — that's harmless without a live tag.)
        let html = payload.draft.htmlBody
        #expect(!html.contains("<img"))
        #expect(!html.contains("onerror=alert(1)>"))
        #expect(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
    }

    @Test("client-side iMIP replies require an organizer")
    func clientSideIMIPRepliesRequireOrganizer() throws {
        let event = try #require(ICSParser.parseFirstEvent(from: Self.inviteWithoutOrganizer))
        let account = BrevAccount.preview

        #expect(throws: CalendarInviteClientReplyComposer.ComposeError.missingOrganizer) {
            _ = try CalendarInviteClientReplyComposer.compose(
                event: event,
                response: .declined,
                account: account,
                messageID: "m1"
            )
        }
    }

    private static let invite = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:event-1
    DTSTART:20260601T120000Z
    DTEND:20260601T130000Z
    SUMMARY:Product review
    ORGANIZER;CN=Alex:mailto:alex@example.org
    ATTENDEE;CN=Henrik:mailto:henrik@example.org
    END:VEVENT
    END:VCALENDAR
    """

    private static let inviteWithMaliciousSummary = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:event-3
    DTSTART:20260601T120000Z
    DTEND:20260601T130000Z
    SUMMARY:<img src=x onerror=alert(1)>
    ORGANIZER;CN=Alex:mailto:alex@example.org
    ATTENDEE;CN=Henrik:mailto:henrik@example.org
    END:VEVENT
    END:VCALENDAR
    """

    private static let inviteWithoutOrganizer = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:event-2
    DTSTART:20260601T120000Z
    SUMMARY:No organizer
    ATTENDEE;CN=Henrik:mailto:henrik@example.org
    END:VEVENT
    END:VCALENDAR
    """
}
