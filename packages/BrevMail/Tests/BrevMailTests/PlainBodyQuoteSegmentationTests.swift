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

@testable import BrevMail
import Foundation
import Testing

@Suite("PlainBodyQuoteSegmentation")
struct PlainBodyQuoteSegmentationTests {
    @Test("sent-copy style body splits reply text from the quoted run")
    func sentCopySplitsAtQuote() {
        let body = "Sounds good, see you then.\n\nOn 1 Jan 2026 at 10:00 UTC, Ingrid <ingrid@example.org> wrote:\n> hello there\n> second line"

        #expect(PlainBodyQuoteSegmentation.segments(of: body) == [
            .text("Sounds good, see you then.\n\nOn 1 Jan 2026 at 10:00 UTC, Ingrid <ingrid@example.org> wrote:"),
            .quote("hello there\nsecond line"),
        ])
    }

    @Test("blank line inside a quote stays in the quote run")
    func blankInsideQuoteStays() {
        #expect(PlainBodyQuoteSegmentation.segments(of: "> first\n\n> second") == [
            .quote("first\n\nsecond"),
        ])
    }

    @Test("nested markers collapse to a single run, plain body stays one segment")
    func nestedAndPlain() {
        #expect(PlainBodyQuoteSegmentation.segments(of: "> > deep\n> shallow") == [
            .quote("deep\nshallow"),
        ])
        #expect(PlainBodyQuoteSegmentation.segments(of: "no quotes\nhere") == [
            .text("no quotes\nhere"),
        ])
    }

    @Test("quote at the start, text after")
    func leadingQuoteThenText() {
        #expect(PlainBodyQuoteSegmentation.segments(of: "> quoted\nmy reply") == [
            .quote("quoted"),
            .text("my reply"),
        ])
    }
}
