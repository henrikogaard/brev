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

@Suite("ComposeQuoteEditGuard")
struct ComposeQuoteEditGuardTests {
    private let replyBody = "\n\nOn 1 Jan 2026 at 10:00 UTC, Ingrid <ingrid@example.org> wrote:\n> hello there\n> second line"
    private let marker = "On 1 Jan 2026 at 10:00 UTC, Ingrid <ingrid@example.org> wrote:"

    @Test("edits inside a trailing quote are refused, user area stays editable")
    func trailingQuoteEditsAreRefused() {
        let protection = ComposeQuoteProtection(marker: marker, edge: .bottom)
        let storage = replyBody as NSString
        let markerLocation = storage.range(of: marker).location

        // Typing in the leading empty lines (the user's reply area).
        #expect(ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: 1, length: 0),
            in: storage,
            protection: protection
        ))
        // Typing or deleting inside the quote.
        #expect(!ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: markerLocation + 4, length: 0),
            in: storage,
            protection: protection
        ))
        #expect(!ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: storage.length - 3, length: 3),
            in: storage,
            protection: protection
        ))
        // A selection spanning the boundary is refused as a whole.
        #expect(!ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: markerLocation - 2, length: 4),
            in: storage,
            protection: protection
        ))
    }

    @Test("a leading quote protects marker plus prefixed lines only")
    func leadingQuoteEditsAreRefused() {
        let protection = ComposeQuoteProtection(marker: marker, edge: .top)
        let body =
            "On 1 Jan 2026 at 10:00 UTC, Ingrid <ingrid@example.org> wrote:\n> hello there\n> second line\n\n\nmy reply" as NSString

        #expect(!ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: 3, length: 0),
            in: body,
            protection: protection
        ))
        // Inside the last `> ` line is still protected.
        #expect(!ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: marker.utf16.count + 5, length: 0),
            in: body,
            protection: protection
        ))
        // The blank gap and below are the user's typing zone.
        #expect(ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: body.length - 5, length: 0),
            in: body,
            protection: protection
        ))
    }

    @Test("no protection without the marker, and nil protection allows all")
    func missingMarkerDisablesGuard() {
        let storage = "plain body" as NSString
        let protection = ComposeQuoteProtection(marker: marker, edge: .bottom)

        #expect(ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: 3, length: 0),
            in: storage,
            protection: protection
        ))
        #expect(ComposeQuoteEditGuard.allows(
            changeRange: NSRange(location: 3, length: 0),
            in: storage,
            protection: nil
        ))
    }
}
