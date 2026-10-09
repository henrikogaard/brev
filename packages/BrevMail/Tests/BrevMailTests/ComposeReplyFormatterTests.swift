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
        #expect(ComposeReplyFormatter.subject(for: " \n re: Project notes \n ") == "Re: Project notes")
    }

    @Test("reply subject collapses stacked prefixes")
    func subjectCollapsesStackedPrefixes() {
        #expect(ComposeReplyFormatter.subject(for: "Re: Re: weekend plans") == "Re: weekend plans")
        #expect(ComposeReplyFormatter.subject(for: "RE: re:Re: launch") == "Re: launch")
        #expect(ComposeReplyFormatter.subject(for: "Re:  ") == "Re: (no subject)")
        // Non-reply prefixes are left in place.
        #expect(ComposeReplyFormatter.subject(for: "Fwd: notes") == "Re: Fwd: notes")
        #expect(ComposeReplyFormatter.subject(for: "Real: estate") == "Re: Real: estate")
    }

    @Test("blank reply subject uses a readable fallback")
    func blankSubjectUsesFallback() {
        #expect(ComposeReplyFormatter.subject(for: " \n\t ") == "Re: (no subject)")
    }

    @Test("default reply body leaves reply area above quoted original")
    func defaultBodyLeavesReplyAreaAboveQuotedOriginal() {
        let body = ComposeReplyFormatter.body(
            for: Self.makeHeader(),
            placement: .belowReply,
            locale: Self.english,
            timeZone: Self.utc
        )

        #expect(body == """


        On 28 May 2026 at 9:30, Alex Chen <alex@example.org> wrote:
        > Let's review the launch checklist before Friday.
        """)
    }

    @Test("reply prefill stays in the typing region for either quote placement")
    func replyPrefillStaysInTypingRegionForEitherQuotePlacement() {
        #expect(ComposeReplyPrefillPolicy.bodyText(
            prefillBodyText: "Quick reply",
            replyBody: "\n\nQuoted original",
            placement: .belowReply
        ) == "Quick reply\n\nQuoted original")
        #expect(ComposeReplyPrefillPolicy.bodyText(
            prefillBodyText: "Quick reply",
            replyBody: "Quoted original\n\n",
            placement: .aboveReply
        ) == "Quoted original\n\nQuick reply")
        #expect(ComposeReplyPrefillPolicy.bodyText(
            prefillBodyText: nil,
            replyBody: "Quoted original",
            placement: .belowReply
        ) == "Quoted original")
    }

    @Test("above reply placement puts quoted original before reply area")
    func aboveReplyPlacementPutsQuoteFirst() {
        let body = ComposeReplyFormatter.body(
            for: Self.makeHeader(),
            placement: .aboveReply,
            locale: Self.english,
            timeZone: Self.utc
        )

        #expect(body == """
        On 28 May 2026 at 9:30, Alex Chen <alex@example.org> wrote:
        > Let's review the launch checklist before Friday.


        """)
    }

    @Test("reply body uses explicit decoded quote text over listing snippet")
    func bodyUsesExplicitDecodedQuoteTextOverListingSnippet() {
        let body = ComposeReplyFormatter.body(
            for: Self.makeHeader(snippet: "UmVuZjyDNjyDN"),
            quoteText: "Your Google AI Plus plan has ended.",
            placement: .belowReply,
            locale: Self.english,
            timeZone: Self.utc
        )

        #expect(body.contains("Your Google AI Plus plan has ended."))
        #expect(!body.contains("UmVuZ"))
    }

    @Test("reply body omits quote text when snippet is empty")
    func bodyOmitsQuoteTextWhenSnippetIsEmpty() {
        let body = ComposeReplyFormatter.body(
            for: Self.makeHeader(snippet: " "),
            placement: .belowReply,
            locale: Self.english,
            timeZone: Self.utc
        )

        #expect(body == """


        On 28 May 2026 at 9:30, Alex Chen <alex@example.org> wrote:
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

    @Test("attribution line is localized and uses the reader's local time")
    func attributionIsLocalizedAndLocalTime() {
        let header = Self.makeHeader()
        let norwegian = ComposeReplyFormatter.quoteMarker(
            for: header,
            locale: Locale(identifier: "nb"),
            timeZone: TimeZone(identifier: "Europe/Oslo")!
        )
        #expect(norwegian == "Den 28. mai 2026 kl. 11:30 skrev Alex Chen <alex@example.org>:")

        let english = ComposeReplyFormatter.quoteMarker(
            for: header,
            locale: Self.english,
            timeZone: TimeZone(identifier: "Europe/Oslo")!
        )
        #expect(english == "On 28 May 2026 at 11:30, Alex Chen <alex@example.org> wrote:")
    }

    @Test("the quote marker is the first line of the reply body in every language")
    func markerIsFirstQuoteLine() {
        let header = Self.makeHeader()
        let locale = Locale(identifier: "nb")
        let marker = ComposeReplyFormatter.quoteMarker(for: header, locale: locale, timeZone: Self.utc)
        let body = ComposeReplyFormatter.body(
            for: header,
            placement: .belowReply,
            locale: locale,
            timeZone: Self.utc
        )
        #expect(body.hasPrefix("\n\n\(marker)\n> "))
    }

    @Test("the quote edit guard still locates a localized quote")
    func guardLocatesLocalizedQuote() {
        let header = Self.makeHeader()
        let locale = Locale(identifier: "nb")
        let marker = ComposeReplyFormatter.quoteMarker(for: header, locale: locale, timeZone: Self.utc)
        let body = ComposeReplyFormatter.body(
            for: header,
            placement: .belowReply,
            locale: locale,
            timeZone: Self.utc
        ) as NSString
        let range = ComposeQuoteEditGuard.protectedRange(
            in: body,
            protection: ComposeQuoteProtection(marker: marker, edge: .bottom)
        )
        #expect(range?.location == 2)
    }

    @Test("English and localized attribution lines are both recognised")
    func recognisesAttributionLines() {
        #expect(ComposeReplyFormatter.isAttributionLine("On Jan 1, Ada wrote:"))
        #expect(ComposeReplyFormatter.isAttributionLine(
            ComposeReplyFormatter.quoteMarker(
                for: Self.makeHeader(),
                locale: Locale(identifier: "nb"),
                timeZone: Self.utc
            ),
            locale: Locale(identifier: "nb")
        ))
        #expect(!ComposeReplyFormatter.isAttributionLine("On my way, see you soon"))
        #expect(!ComposeReplyFormatter.isAttributionLine("Den lange veien hjem"))
    }

    private static let english = Locale(identifier: "en_GB")
    private static let utc = TimeZone(identifier: "UTC")!

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
