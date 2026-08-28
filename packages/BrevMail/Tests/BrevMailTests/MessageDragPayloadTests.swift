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
import Testing

@Suite("Message drag payload")
struct MessageDragPayloadTests {
    @Test("source message payloads round trip through a string representation")
    func sourceMessagePayloadsRoundTrip() throws {
        let payload = SourceMessageDragPayload(
            sourceID: MailSourceID(accountID: "account", mailboxID: "mailbox"),
            messageID: "message-1"
        )

        let decoded = try #require(SourceMessageDragPayload(encodedRepresentation: payload.encodedRepresentation))

        #expect(decoded == payload)
    }

    @Test("plain message ids remain supported for legacy single-source drops")
    func plainMessageIDsRemainSupported() {
        let route = MessageDropRoutingPolicy.route(
            ["message-1", "message-2"],
            destinationSourceID: nil,
            selectedSourceID: nil
        )

        #expect(route == .plain(messageIDs: ["message-1", "message-2"]))
    }

    @Test("source payloads route only when dropped on their owning source")
    func sourcePayloadsRouteOnlyToOwningSource() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let otherSourceID = MailSourceID(accountID: "account", mailboxID: "other")
        let payload = SourceMessageDragPayload(
            sourceID: sourceID,
            messageID: "message-1"
        )

        let route = MessageDropRoutingPolicy.route(
            [payload.encodedRepresentation],
            destinationSourceID: sourceID,
            selectedSourceID: nil
        )
        let rejectedRoute = MessageDropRoutingPolicy.route(
            [payload.encodedRepresentation],
            destinationSourceID: otherSourceID,
            selectedSourceID: nil
        )

        #expect(route == .source(sourceID: sourceID, messageIDs: ["message-1"]))
        #expect(rejectedRoute == nil)
    }

    @Test("plain source-tree drops use the selected source as the owner")
    func plainSourceTreeDropsUseSelectedSourceAsOwner() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let route = MessageDropRoutingPolicy.route(
            ["message-1"],
            destinationSourceID: sourceID,
            selectedSourceID: sourceID
        )

        #expect(route == .source(sourceID: sourceID, messageIDs: ["message-1"]))
    }

    @Test("plain source-tree drops are rejected when selection belongs to another source")
    func plainSourceTreeDropsRejectCrossSourceSelection() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let otherSourceID = MailSourceID(accountID: "account", mailboxID: "other")
        let route = MessageDropRoutingPolicy.route(
            ["message-1"],
            destinationSourceID: otherSourceID,
            selectedSourceID: sourceID
        )

        #expect(route == nil)
    }
}
