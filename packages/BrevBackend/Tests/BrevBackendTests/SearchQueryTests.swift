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

@Suite("SearchQuery.matches(_:)")
struct SearchQueryMatchesTests {
    // MARK: - Fixture

    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func makeHeader(
        id: String = "h1",
        subject: String = "Meeting notes",
        from: Correspondent = Correspondent(name: "Alice", email: "alice@example.com"),
        to: [Correspondent] = [Correspondent(name: "Bob", email: "bob@example.com")],
        cc: [Correspondent] = [],
        bcc: [Correspondent] = [],
        snippet: String = "See the attached agenda",
        date: Date = epoch,
        isRead: Bool = true,
        isFlagged: Bool = false,
        hasAttachments: Bool = false,
        folderID: String = "inbox"
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "t1",
            folderID: folderID,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            snippet: snippet,
            date: date,
            isRead: isRead,
            isFlagged: isFlagged,
            hasAttachments: hasAttachments
        )
    }

    // MARK: - Empty query

    @Test("empty query matches every header")
    func emptyQueryMatchesEveryHeader() {
        let query = SearchQuery()
        #expect(query.matches(Self.makeHeader()))
    }

    // MARK: - Text

    @Test("text filter matches subject")
    func textFilterMatchesSubject() {
        let query = SearchQuery(text: "meeting")
        #expect(query.matches(Self.makeHeader(subject: "Meeting notes")))
        #expect(!query.matches(Self.makeHeader(subject: "Invoice")))
    }

    @Test("text filter matches snippet")
    func textFilterMatchesSnippet() {
        let query = SearchQuery(text: "agenda")
        #expect(query.matches(Self.makeHeader(snippet: "See the attached agenda")))
        #expect(!query.matches(Self.makeHeader(snippet: "No items here")))
    }

    @Test("text filter matches sender email")
    func textFilterMatchesSenderEmail() {
        let query = SearchQuery(text: "alice@example")
        let alice = Correspondent(name: "Alice", email: "alice@example.com")
        #expect(query.matches(Self.makeHeader(from: alice)))
    }

    @Test("text filter is case-insensitive")
    func textFilterIsCaseInsensitive() {
        let query = SearchQuery(text: "MEETING")
        #expect(query.matches(Self.makeHeader(subject: "meeting notes")))
    }

    @Test("text filter is diacritic-insensitive")
    func textFilterIsDiacriticInsensitive() {
        let query = SearchQuery(text: "mote")
        #expect(query.matches(Self.makeHeader(subject: "Møteplan")))
    }

    @Test("text filter ignores surrounding whitespace")
    func textFilterIgnoresSurroundingWhitespace() {
        let query = SearchQuery(text: "  meeting  ")
        #expect(query.matches(Self.makeHeader(subject: "Meeting notes")))
    }

    // MARK: - Subject

    @Test("subject filter matches subject substring")
    func subjectFilterMatchesSubjectSubstring() {
        let query = SearchQuery(subject: "notes")
        #expect(query.matches(Self.makeHeader(subject: "Meeting notes")))
        #expect(!query.matches(Self.makeHeader(subject: "Invoice")))
    }

    @Test("subject filter ignores surrounding whitespace")
    func subjectFilterIgnoresSurroundingWhitespace() {
        let query = SearchQuery(subject: "  notes  ")
        #expect(query.matches(Self.makeHeader(subject: "Meeting notes")))
    }

    @Test("subject filter is diacritic-insensitive")
    func subjectFilterIsDiacriticInsensitive() {
        let query = SearchQuery(subject: "arsrapport")
        #expect(query.matches(Self.makeHeader(subject: "Årsrapport")))
    }

    // MARK: - isUnread

    @Test("isUnread=true matches unread messages")
    func isUnreadTrueMatchesUnreadMessages() {
        let query = SearchQuery(isUnread: true)
        #expect(query.matches(Self.makeHeader(isRead: false)))
        #expect(!query.matches(Self.makeHeader(isRead: true)))
    }

    @Test("isUnread=false matches read messages")
    func isUnreadFalseMatchesReadMessages() {
        let query = SearchQuery(isUnread: false)
        #expect(query.matches(Self.makeHeader(isRead: true)))
        #expect(!query.matches(Self.makeHeader(isRead: false)))
    }

    @Test("isUnread=nil imposes no read-state constraint")
    func isUnreadNilImposesNoConstraint() {
        let query = SearchQuery(isUnread: nil)
        #expect(query.matches(Self.makeHeader(isRead: true)))
        #expect(query.matches(Self.makeHeader(isRead: false)))
    }

    // MARK: - isFlagged

    @Test("isFlagged=true matches flagged messages")
    func isFlaggedTrueMatchesFlaggedMessages() {
        let query = SearchQuery(isFlagged: true)
        #expect(query.matches(Self.makeHeader(isFlagged: true)))
        #expect(!query.matches(Self.makeHeader(isFlagged: false)))
    }

    @Test("isFlagged=false matches unflagged messages")
    func isFlaggedFalseMatchesUnflaggedMessages() {
        let query = SearchQuery(isFlagged: false)
        #expect(query.matches(Self.makeHeader(isFlagged: false)))
        #expect(!query.matches(Self.makeHeader(isFlagged: true)))
    }

    // MARK: - hasAttachments

    @Test("hasAttachments=true matches messages with attachments")
    func hasAttachmentsTrueMatchesMessagesWithAttachments() {
        let query = SearchQuery(hasAttachments: true)
        #expect(query.matches(Self.makeHeader(hasAttachments: true)))
        #expect(!query.matches(Self.makeHeader(hasAttachments: false)))
    }

    // MARK: - folderID

    @Test("folderID filter restricts to the matching folder")
    func folderIDFilterRestrictsToMatchingFolder() {
        let query = SearchQuery(folderID: "inbox")
        #expect(query.matches(Self.makeHeader(folderID: "inbox")))
        #expect(!query.matches(Self.makeHeader(folderID: "sent")))
    }

    // MARK: - dateRange

    @Test("dateRange filter restricts messages to the given window")
    func dateRangeFilterRestrictsToGivenWindow() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 2000)
        let query = SearchQuery(dateRange: start ... end)

        #expect(query.matches(Self.makeHeader(date: Date(timeIntervalSince1970: 1500))))
        #expect(!query.matches(Self.makeHeader(date: Date(timeIntervalSince1970: 500))))
        #expect(!query.matches(Self.makeHeader(date: Date(timeIntervalSince1970: 2500))))
    }

    // MARK: - from / to

    @Test("from filter matches sender by partial email")
    func fromFilterMatchesSenderByPartialEmail() {
        let alice = Correspondent(name: "Alice", email: "alice@example.com")
        let query = SearchQuery(from: "alice@example")
        #expect(query.matches(Self.makeHeader(from: alice)))
        let bob = Correspondent(name: "Bob", email: "bob@other.com")
        #expect(!query.matches(Self.makeHeader(from: bob)))
    }

    @Test("from filter ignores surrounding whitespace")
    func fromFilterIgnoresSurroundingWhitespace() {
        let alice = Correspondent(name: "Alice", email: "alice@example.com")
        let query = SearchQuery(from: "  alice@example  ")
        #expect(query.matches(Self.makeHeader(from: alice)))
    }

    @Test("from filter is diacritic-insensitive")
    func fromFilterIsDiacriticInsensitive() {
        let sender = Correspondent(name: "Søren", email: "soren@example.com")
        let query = SearchQuery(from: "soren")
        #expect(query.matches(Self.makeHeader(from: sender)))
    }

    @Test("to filter matches recipient by partial email")
    func toFilterMatchesRecipientByPartialEmail() {
        let bob = Correspondent(name: "Bob", email: "bob@example.com")
        let query = SearchQuery(to: "bob@example")
        #expect(query.matches(Self.makeHeader(to: [bob])))
        let other = Correspondent(name: "Carol", email: "carol@other.com")
        #expect(!query.matches(Self.makeHeader(to: [other])))
    }

    @Test("to filter ignores surrounding whitespace")
    func toFilterIgnoresSurroundingWhitespace() {
        let bob = Correspondent(name: "Bob", email: "bob@example.com")
        let query = SearchQuery(to: "  bob@example  ")
        #expect(query.matches(Self.makeHeader(to: [bob])))
    }

    @Test("to filter is diacritic-insensitive")
    func toFilterIsDiacriticInsensitive() {
        let recipient = Correspondent(name: "Bjørn", email: "bjorn@example.com")
        let query = SearchQuery(to: "bjorn")
        #expect(query.matches(Self.makeHeader(to: [recipient])))
    }

    @Test("to filter matches cc recipient by partial email")
    func toFilterMatchesCcRecipientByPartialEmail() {
        let carol = Correspondent(name: "Carol", email: "carol@example.com")
        let query = SearchQuery(to: "carol@example")
        #expect(query.matches(Self.makeHeader(to: [], cc: [carol])))
    }

    @Test("to filter matches bcc recipient by partial email")
    func toFilterMatchesBccRecipientByPartialEmail() {
        let hidden = Correspondent(name: "Hidden", email: "hidden@example.com")
        let query = SearchQuery(to: "hidden@example")
        #expect(query.matches(Self.makeHeader(to: [], bcc: [hidden])))
    }

    // MARK: - Combined predicates

    @Test("combined predicates all must match")
    func combinedPredicatesAllMustMatch() {
        let query = SearchQuery(
            text: "notes",
            isUnread: true,
            isFlagged: true
        )
        // Unread + flagged + text match → passes
        #expect(query.matches(Self.makeHeader(
            subject: "Meeting notes",
            isRead: false,
            isFlagged: true
        )))
        // Unread + flagged but no text → fails
        #expect(!query.matches(Self.makeHeader(
            subject: "Invoice",
            isRead: false,
            isFlagged: true
        )))
    }
}
