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

import BrevMail
import Foundation
import Testing

@Suite("ShareHandoffURL")
struct ShareHandoffURLTests {
    @Test("builds a brev://compose URL carrying the shared payload")
    func buildsComposeURL() throws {
        let url = try #require(
            ShareHandoffURL.url(
                text: "check this out",
                urls: [URL(string: "https://example.org/article")!],
                attachments: [URL(fileURLWithPath: "/tmp/ShareHandoff/x/a.pdf")]
            )
        )

        #expect(url.scheme == "brev")
        #expect(url.host == "compose")
        let shared = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "shared" })?.value
        #expect(shared?.isEmpty == false)
    }

    @Test("an empty share produces no URL")
    func emptyShareProducesNoURL() {
        #expect(ShareHandoffURL.url(text: nil, urls: [], attachments: []) == nil)
        #expect(ShareHandoffURL.url(text: "", urls: [], attachments: []) == nil)
        #expect(ShareHandoffURL.payload(text: nil, urls: [], attachments: []).isEmpty)
    }

    @Test("text and links round-trip through the app-side parser")
    func payloadRoundTrips() throws {
        let url = try #require(
            ShareHandoffURL.url(
                text: "hello & goodbye",
                urls: [URL(string: "https://example.org/path?q=1&r=2")!],
                attachments: []
            )
        )

        let prefill = try #require(SharedComposePayload.prefill(from: url))
        #expect(prefill.bodyText == "hello & goodbye\n\nhttps://example.org/path?q=1&r=2")
        #expect(prefill.attachmentFileURLs.isEmpty)
    }

    @Test("attachment file URLs outside the handoff root are rejected by the parser")
    func attachmentsOutsideHandoffRootRejected() throws {
        // The payload carries the attachment item, but `SharedComposePayload`
        // confines attachments to the app-group handoff directory — a file URL
        // anywhere else must not be attached (fail safe).
        let url = try #require(
            ShareHandoffURL.url(
                text: nil,
                urls: [],
                attachments: [URL(fileURLWithPath: "/tmp/not-a-handoff-dir/outside.pdf")]
            )
        )

        #expect(SharedComposePayload.prefill(from: url) == nil)
    }

    @Test("text at the 256 KB handoff limit is accepted")
    func textAtLimitAccepted() {
        let text = String(repeating: "x", count: ShareHandoffURL.maximumSharedTextBytes)
        #expect(ShareHandoffURL.canHandoff(text: text))
    }

    @Test("text above the 256 KB limit is excluded — never truncated")
    func textAboveLimitRejected() {
        let text = String(repeating: "x", count: ShareHandoffURL.maximumSharedTextBytes + 1)
        #expect(!ShareHandoffURL.canHandoff(text: text))
    }

    @Test("UTF-8 bytes, not characters, count toward the limit")
    func multiByteCharactersCountedAsBytes() {
        // "å" is two UTF-8 bytes, so half the cap in characters already
        // exceeds the byte budget.
        let text = String(repeating: "å", count: ShareHandoffURL.maximumSharedTextBytes / 2 + 1)
        #expect(!ShareHandoffURL.canHandoff(text: text))
    }
}

@Suite("ShareHandoffReservation")
struct ShareHandoffReservationTests {
    @Test("reservations are granted until the byte cap is reached")
    func byteCapEnforced() {
        let reservation = ShareHandoffReservation(maximumCount: 10, maximumBytes: 100)

        #expect(reservation.reserve(bytes: 60))
        #expect(reservation.reserve(bytes: 40))
        #expect(!reservation.reserve(bytes: 1))
    }

    @Test("the attachment count cap is enforced")
    func countCapEnforced() {
        let reservation = ShareHandoffReservation(maximumCount: 2, maximumBytes: .max)

        #expect(reservation.reserve(bytes: 1))
        #expect(reservation.reserve(bytes: 1))
        #expect(!reservation.reserve(bytes: 1))
    }

    @Test("a rejected reservation consumes no budget")
    func rejectedReservationConsumesNothing() {
        let reservation = ShareHandoffReservation(maximumCount: 2, maximumBytes: 10)

        #expect(!reservation.reserve(bytes: 11))
        #expect(reservation.reserve(bytes: 10))
    }
}
