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

import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

/// URL builder/parser coverage for the PIM deep links (#10): the
/// round trip must preserve opaque record IDs and the parser must
/// fail closed on foreign schemes, unknown hosts, and blank IDs.
@Suite("PIMDeepLinkPolicy")
struct PIMDeepLinkPolicyTests {
    @Test("an event link round-trips an opaque record ID")
    func eventLinkRoundTrips() throws {
        let id = PIMEvent.makeID(
            collectionID: "cal|c1",
            providerItemKey: "item|9",
            recurrenceID: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let url = try #require(PIMDeepLinkPolicy.url(forEventID: id))
        #expect(url.scheme == "brev")
        #expect(url.host == "event")
        #expect(PIMDeepLinkPolicy.link(from: url) == .event(id: id))
    }

    @Test("a contact link round-trips an opaque record ID")
    func contactLinkRoundTrips() throws {
        let id = PIMContact.makeID(
            sourceID: "src|1",
            providerItemKey: "people/c123"
        )
        let url = try #require(PIMDeepLinkPolicy.url(forContactID: id))
        #expect(url.scheme == "brev")
        #expect(url.host == "contact")
        #expect(PIMDeepLinkPolicy.link(from: url) == .contact(id: id))
    }

    @Test("percent-encoded IDs decode back to the record ID")
    func encodedIDsDecode() throws {
        let url = try #require(
            URL(string: "brev://event?id=c1%7Citem%7C123")
        )
        #expect(
            PIMDeepLinkPolicy.link(from: url)
                == .event(id: "c1|item|123")
        )
    }

    @Test("foreign schemes, unknown hosts, and blank IDs fail closed")
    func malformedLinksRejected() throws {
        // brev://message is the mail route — never a PIM link.
        let message = try #require(
            URL(string: "brev://message?accountID=a&folderID=f&messageID=m")
        )
        #expect(PIMDeepLinkPolicy.link(from: message) == nil)

        let web = try #require(URL(string: "https://example.com/event?id=x"))
        #expect(PIMDeepLinkPolicy.link(from: web) == nil)

        let noID = try #require(URL(string: "brev://event"))
        #expect(PIMDeepLinkPolicy.link(from: noID) == nil)

        let blankID = try #require(URL(string: "brev://event?id=%20%20"))
        #expect(PIMDeepLinkPolicy.link(from: blankID) == nil)

        let unknownHost = try #require(URL(string: "brev://folder?id=x"))
        #expect(PIMDeepLinkPolicy.link(from: unknownHost) == nil)
    }
}
