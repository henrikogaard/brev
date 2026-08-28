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

@Suite("MessageSearchFallback")
struct MessageSearchFallbackTests {
    @Test("blank queries keep all loaded headers")
    func blankQueriesKeepAllLoadedHeaders() {
        let first = Self.makeHeader(id: "first", subject: "Roadmap", sender: "Ada")
        let second = Self.makeHeader(id: "second", subject: "Invoice", sender: "Grace")

        #expect(MessageSearchFallback.filteredHeaders(
            in: [first, second],
            query: " "
        ).map(\.id) == [first.id, second.id])
    }

    @Test("local fallback matches subjects case insensitively")
    func localFallbackMatchesSubjectsCaseInsensitively() {
        let match = Self.makeHeader(id: "match", subject: "Quarterly Budget", sender: "Ada")
        let miss = Self.makeHeader(id: "miss", subject: "Roadmap", sender: "Grace")

        #expect(MessageSearchFallback.filteredHeaders(
            in: [match, miss],
            query: "budget"
        ).map(\.id) == [match.id])
    }

    @Test("local fallback matches sender display names case insensitively")
    func localFallbackMatchesSenderDisplayNamesCaseInsensitively() {
        let match = Self.makeHeader(id: "match", subject: "Roadmap", sender: "Ada Lovelace")
        let miss = Self.makeHeader(id: "miss", subject: "Roadmap", sender: "Grace Hopper")

        #expect(MessageSearchFallback.filteredHeaders(
            in: [match, miss],
            query: "LOVELACE"
        ).map(\.id) == [match.id])
    }

    @Test("local fallback matches snippets")
    func localFallbackMatchesSnippets() {
        let match = Self.makeHeader(
            id: "match",
            subject: "Roadmap",
            sender: "Ada",
            snippet: "Calendar invite attached."
        )
        let miss = Self.makeHeader(
            id: "miss",
            subject: "Roadmap",
            sender: "Grace",
            snippet: "No attachments here."
        )

        #expect(MessageSearchFallback.filteredHeaders(
            in: [match, miss],
            query: "invite"
        ).map(\.id) == [match.id])
    }

    @Test("local fallback matches sender email addresses")
    func localFallbackMatchesSenderEmailAddresses() {
        let match = Self.makeHeader(
            id: "match",
            subject: "Roadmap",
            sender: "Ada",
            senderEmail: "ada@research.example"
        )
        let miss = Self.makeHeader(
            id: "miss",
            subject: "Roadmap",
            sender: "Grace",
            senderEmail: "grace@example.com"
        )

        #expect(MessageSearchFallback.filteredHeaders(
            in: [match, miss],
            query: "research.example"
        ).map(\.id) == [match.id])
    }

    @Test("local fallback matches visible recipients")
    func localFallbackMatchesVisibleRecipients() {
        let match = Self.makeHeader(
            id: "match",
            subject: "Roadmap",
            sender: "Ada",
            to: [Correspondent(name: "Henrik", email: "henrik@example.org")],
            cc: [Correspondent(name: "Review Crew", email: "review@example.org")]
        )
        let miss = Self.makeHeader(
            id: "miss",
            subject: "Roadmap",
            sender: "Grace",
            to: [Correspondent(name: "Ada", email: "ada@example.org")]
        )

        #expect(MessageSearchFallback.filteredHeaders(
            in: [match, miss],
            query: "review@example"
        ).map(\.id) == [match.id])
    }

    @Test("rich local fallback preserves structured predicates")
    func richLocalFallbackPreservesStructuredPredicates() {
        let match = Self.makeHeader(
            id: "match",
            subject: "Receipt",
            sender: "Ada",
            to: [Correspondent(email: "henrik@example.org")],
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false,
            hasAttachments: true
        )
        let wrongRecipient = Self.makeHeader(
            id: "wrong-recipient",
            subject: "Receipt",
            sender: "Ada",
            to: [Correspondent(email: "other@example.org")],
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false,
            hasAttachments: true
        )
        let wrongState = Self.makeHeader(
            id: "wrong-state",
            subject: "Receipt",
            sender: "Ada",
            to: [Correspondent(email: "henrik@example.org")],
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: true,
            hasAttachments: true
        )
        let wrongAttachmentState = Self.makeHeader(
            id: "wrong-attachment-state",
            subject: "Receipt",
            sender: "Ada",
            to: [Correspondent(email: "henrik@example.org")],
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false,
            hasAttachments: false
        )
        let outsideDateRange = Self.makeHeader(
            id: "outside-date-range",
            subject: "Receipt",
            sender: "Ada",
            to: [Correspondent(email: "henrik@example.org")],
            date: Date(timeIntervalSince1970: 1_600_000_000),
            isRead: false,
            hasAttachments: true
        )

        let query = SearchQuery(
            to: "henrik@example.org",
            dateRange: Date(timeIntervalSince1970: 1_699_999_000) ... Date(timeIntervalSince1970: 1_700_001_000),
            hasAttachments: true,
            isUnread: true,
            subject: "receipt",
            execution: .cacheThenServer
        )

        #expect(MessageSearchFallback.filteredHeaders(
            in: [match, wrongRecipient, wrongState, wrongAttachmentState, outsideDateRange],
            searchQuery: query
        ).map(\.id) == [match.id])
    }

    private static func makeHeader(
        id: String,
        subject: String,
        sender: String,
        senderEmail: String? = nil,
        snippet: String = "",
        to: [Correspondent] = [],
        cc: [Correspondent] = [],
        bcc: [Correspondent] = [],
        date: Date = Date(timeIntervalSince1970: 0),
        isRead: Bool = false,
        hasAttachments: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: sender, email: senderEmail ?? "\(id)@example.com"),
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            snippet: snippet,
            date: date,
            isRead: isRead,
            hasAttachments: hasAttachments
        )
    }
}
