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

@Suite("DetachedMailWindowPayload")
struct DetachedMailWindowPayloadTests {
    // A real MailSourceID for use in round-trip tests.
    private let sampleSourceID = MailSourceID(accountID: "imap-smtp:test@example.com", mailboxID: "mbx-1")

    @Test("reader payload round-trips through Codable")
    func readerRoundTrip() throws {
        let payload = DetachedReaderWindowPayload(sourceID: nil, messageID: "msg-7")
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(DetachedReaderWindowPayload.self, from: data) == payload)
    }

    @Test("reader payload with non-nil sourceID round-trips through Codable")
    func readerRoundTripWithSourceID() throws {
        let payload = DetachedReaderWindowPayload(sourceID: sampleSourceID, messageID: "msg-7")
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(DetachedReaderWindowPayload.self, from: data) == payload)
    }

    @Test("compose payload preserves reply intent and message reference")
    func composeRoundTrip() throws {
        let payload = ComposeWindowPayload(kind: .reply(messageID: "m1", sourceID: nil))
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ComposeWindowPayload.self, from: data)
        let expectedKind = ComposeWindowPayload.Kind.reply(messageID: "m1", sourceID: nil)
        #expect(decoded == payload)
        #expect(decoded.kind == expectedKind)
    }

    @Test("new-compose payload is distinct from reply payloads")
    func newComposeDistinct() {
        #expect(ComposeWindowPayload(kind: .new(sourceID: nil))
            != ComposeWindowPayload(kind: .reply(messageID: "m", sourceID: nil)))
    }

    @Test("new-compose window identity is per-source: same source coalesces, different sources don't")
    func newComposeIdentityIsPerSource() {
        let a = MailSourceID(accountID: "acct-a", mailboxID: "acct-a")
        let b = MailSourceID(accountID: "acct-b", mailboxID: "acct-b")
        // Same selected source → equal payload → SwiftUI raises the existing window.
        #expect(ComposeWindowPayload(kind: .new(sourceID: a)) == ComposeWindowPayload(kind: .new(sourceID: a)))
        // Different selected source → distinct window, composing as that account.
        #expect(ComposeWindowPayload(kind: .new(sourceID: a)) != ComposeWindowPayload(kind: .new(sourceID: b)))
        #expect(ComposeWindowPayload(kind: .new(sourceID: a)) != ComposeWindowPayload(kind: .new(sourceID: nil)))
    }

    @Test("compose reply payload with non-nil sourceID round-trips through Codable")
    func composeReplyWithSourceIDRoundTrip() throws {
        let payload = ComposeWindowPayload(kind: .reply(messageID: "m2", sourceID: sampleSourceID))
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ComposeWindowPayload.self, from: data)
        #expect(decoded == payload)
        #expect(decoded.kind == .reply(messageID: "m2", sourceID: sampleSourceID))
    }
}
