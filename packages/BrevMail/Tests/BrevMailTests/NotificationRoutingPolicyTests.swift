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

@Suite("NotificationRoutingPolicy")
struct NotificationRoutingPolicyTests {
    @Test("payload route includes account folder and message identifiers")
    func payloadRouteIncludesStableIdentifiers() {
        let payload = NewMailNotificationPolicy.contentPayload(
            correspondent: .init(name: "Maja Holm", email: "maja@example.org"),
            subject: "Standup notes",
            snippet: "Can we pull the UI polish task before lunch?",
            receivedAt: Date(timeIntervalSince1970: 0),
            messageID: "msg-1",
            accountID: "acct-1",
            folderID: "inbox",
            sourceID: MailSourceID(accountID: "acct-1", mailboxID: "mailbox-1"),
            folderName: "Inbox",
            showPreviews: true,
            playSound: true
        )

        #expect(payload.userInfo["accountID"] == "acct-1")
        #expect(payload.userInfo["folderID"] == "inbox")
        #expect(payload.userInfo["messageID"] == "msg-1")
        #expect(payload.userInfo["sourceAccountID"] == "acct-1")
        #expect(payload.userInfo["sourceMailboxID"] == "mailbox-1")
    }

    @Test("parses route from notification userInfo")
    func parsesRouteFromNotificationUserInfo() {
        let route = NotificationRoutingPolicy.route(from: [
            "accountID": "acct-1",
            "folderID": "inbox",
            "messageID": "msg-1",
            "sourceAccountID": "acct-1",
            "sourceMailboxID": "mailbox-1",
        ])

        #expect(route == NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1",
            sourceID: MailSourceID(accountID: "acct-1", mailboxID: "mailbox-1")
        ))
    }

    @Test("serializes a route with the same stable keys the parser consumes")
    func serializesRouteForNotificationUserInfo() {
        let route = NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1",
            sourceID: MailSourceID(accountID: "acct-1", mailboxID: "mailbox-1")
        )

        let userInfo = NotificationRoutingPolicy.userInfo(for: route)

        #expect(NotificationRoutingPolicy.route(from: userInfo) == route)
        #expect(userInfo.keys.sorted() == [
            "accountID",
            "folderID",
            "messageID",
            "sourceAccountID",
            "sourceMailboxID",
        ])
    }

    @Test("rejects route when stable identifiers are missing")
    func rejectsRouteWhenStableIdentifiersAreMissing() {
        #expect(NotificationRoutingPolicy.route(from: ["messageID": "msg-1"]) == nil)
        #expect(NotificationRoutingPolicy.route(from: ["accountID": "acct-1"]) == nil)
    }

    @Test("parses route from message deep link URL")
    func parsesRouteFromMessageDeepLinkURL() throws {
        let url =
            try #require(
                URL(
                    string: "brev://message?accountID=acct-1&folderID=inbox&messageID=msg-1&sourceAccountID=acct-1&sourceMailboxID=mailbox-1"
                )
            )

        #expect(NotificationRoutingPolicy.route(from: url) == NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1",
            sourceID: MailSourceID(accountID: "acct-1", mailboxID: "mailbox-1")
        ))
    }

    @Test("accepts message deep links with an uppercase scheme")
    func parsesRouteFromMessageDeepLinkURLWithUppercaseScheme() throws {
        let url = try #require(URL(
            string: "BREV://message?accountID=acct-1&folderID=inbox&messageID=msg-1"
        ))

        #expect(NotificationRoutingPolicy.route(from: url) == NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1"
        ))
    }

    @Test("message deep link URL tolerates duplicate query items")
    func messageDeepLinkURLToleratesDuplicateQueryItems() throws {
        let url = try #require(URL(
            string: "brev://message?accountID=acct-1&folderID=inbox&messageID=msg-1&messageID=duplicate"
        ))

        #expect(NotificationRoutingPolicy.route(from: url) == NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1"
        ))
    }

    @Test("rejects non-message deep link URLs")
    func rejectsNonMessageDeepLinkURLs() throws {
        let composeURL = try #require(URL(string: "brev://compose?shared=text%3DHi"))
        let incompleteURL = try #require(URL(string: "brev://message?accountID=acct-1&messageID=msg-1"))

        #expect(NotificationRoutingPolicy.route(from: composeURL) == nil)
        #expect(NotificationRoutingPolicy.route(from: incompleteURL) == nil)
    }

    @Test("resolves exact message when folder and header are available")
    func resolvesExactMessageWhenFolderAndHeaderAreAvailable() {
        let decision = NotificationRoutingPolicy.navigationDecision(
            for: NotificationMailRoute(accountID: "acct-1", folderID: "inbox", messageID: "msg-1"),
            folders: [Self.inbox],
            visibleHeaders: [Self.message(id: "msg-1", folderID: "inbox")]
        )

        #expect(decision == .message(folderID: "inbox", messageID: "msg-1"))
    }

    @Test("falls back to folder when message is stale or not loaded")
    func fallsBackToFolderWhenMessageIsStaleOrNotLoaded() {
        let decision = NotificationRoutingPolicy.navigationDecision(
            for: NotificationMailRoute(accountID: "acct-1", folderID: "inbox", messageID: "stale"),
            folders: [Self.inbox],
            visibleHeaders: [Self.message(id: "msg-1", folderID: "inbox")]
        )

        #expect(decision == .folder(folderID: "inbox"))
    }

    @Test("falls back to unified inbox when folder is unavailable")
    func fallsBackToUnifiedInboxWhenFolderIsUnavailable() {
        let decision = NotificationRoutingPolicy.navigationDecision(
            for: NotificationMailRoute(accountID: "acct-1", folderID: "missing", messageID: "msg-1"),
            folders: [Self.inbox],
            visibleHeaders: [Self.message(id: "msg-1", folderID: "inbox")]
        )

        #expect(decision == .unifiedInbox)
    }

    @Test("notification action decisions are explicit")
    func notificationActionDecisionsAreExplicit() {
        #expect(NotificationActionPolicy.decision(for: .markRead) == .backgroundMutation)
        #expect(NotificationActionPolicy.decision(for: .archive) == .backgroundMutation)
        #expect(NotificationActionPolicy.decision(for: .reply) == .backgroundMutation)
        #expect(NotificationActionPolicy.decision(for: .snooze) == .deferred(reason: "Snooze needs a duration picker."))
    }

    private static let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

    private static func message(id: String, folderID: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: .init(name: "Maja Holm", email: "maja@example.org"),
            subject: "Subject",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 0)
        )
    }
}
