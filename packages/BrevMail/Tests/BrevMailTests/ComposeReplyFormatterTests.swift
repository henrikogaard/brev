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

@Suite("ComposeReplyFormatter")
struct ComposeReplyFormatterTests {
    @Test("reply subject adds prefix once")
    func subjectAddsPrefixOnce() {
        #expect(ComposeReplyFormatter.subject(for: "Project notes") == "Re: Project notes")
        #expect(ComposeReplyFormatter.subject(for: " \n re: Project notes \n ") == "re: Project notes")
    }

    @Test("blank reply subject uses a readable fallback")
    func blankSubjectUsesFallback() {
        #expect(ComposeReplyFormatter.subject(for: " \n\t ") == "Re: (no subject)")
    }

    @Test("default reply body leaves reply area above quoted original")
    func defaultBodyLeavesReplyAreaAboveQuotedOriginal() {
        let body = ComposeReplyFormatter.body(for: Self.makeHeader(), placement: .belowReply)

        #expect(body == """


        On 28 May 2026 at 09:30 UTC, Alex Chen <alex@example.org> wrote:
        > Let's review the launch checklist before Friday.
        """)
    }

    @Test("above reply placement puts quoted original before reply area")
    func aboveReplyPlacementPutsQuoteFirst() {
        let body = ComposeReplyFormatter.body(for: Self.makeHeader(), placement: .aboveReply)

        #expect(body == """
        On 28 May 2026 at 09:30 UTC, Alex Chen <alex@example.org> wrote:
        > Let's review the launch checklist before Friday.


        """)
    }

    @Test("reply body uses explicit decoded quote text over listing snippet")
    func bodyUsesExplicitDecodedQuoteTextOverListingSnippet() {
        let body = ComposeReplyFormatter.body(
            for: Self.makeHeader(snippet: "UmVuZjyDNjyDN"),
            quoteText: "Your Google AI Plus plan has ended.",
            placement: .belowReply
        )

        #expect(body.contains("Your Google AI Plus plan has ended."))
        #expect(!body.contains("UmVuZ"))
    }

    @Test("reply body omits quote text when snippet is empty")
    func bodyOmitsQuoteTextWhenSnippetIsEmpty() {
        let body = ComposeReplyFormatter.body(
            for: Self.makeHeader(snippet: " "),
            placement: .belowReply
        )

        #expect(body == """


        On 28 May 2026 at 09:30 UTC, Alex Chen <alex@example.org> wrote:
        """)
    }

    @Test("quote placement loads stored compose preference")
    func quotePlacementLoadsStoredPreference() throws {
        let suiteName = "ComposeReplyFormatterTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        #expect(ComposeReplyQuotePlacement.load(from: defaults) == .belowReply)

        defaults.set("aboveReply", forKey: ComposeReplyQuotePlacement.storageKey)

        #expect(ComposeReplyQuotePlacement.load(from: defaults) == .aboveReply)

        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func makeHeader(
        snippet: String = "Let's review the launch checklist before Friday."
    ) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex Chen", email: "alex@example.org"),
            subject: "Launch checklist",
            snippet: snippet,
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
