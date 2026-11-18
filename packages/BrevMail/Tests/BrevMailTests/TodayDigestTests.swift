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
import BrevDesign
@testable import BrevMail
import Foundation
import Testing

@Suite("Today digest")
struct TodayDigestTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let source = MailSourceID(accountID: "acct", mailboxID: "box")
    private static let me = Correspondent(name: "Alex Chen", email: "alex@example.org")

    private static func header(
        _ id: String,
        thread: String? = nil,
        folder: String = "inbox",
        from: Correspondent,
        to: [Correspondent] = [me],
        hoursAgo: Double,
        isRead: Bool = false,
        isAnswered: Bool = false,
        messageID: String? = nil,
        inReplyTo: String? = nil,
        references: [String]? = nil
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: thread ?? id,
            folderID: folder,
            from: from,
            to: to,
            subject: "Subject \(id)",
            snippet: "Can you look at this?",
            date: now.addingTimeInterval(-hoursAgo * 3600),
            isRead: isRead,
            isAnswered: isAnswered,
            messageID: messageID,
            inReplyTo: inReplyTo,
            references: references
        )
    }

    private static func build(
        inbox: [MessageHeader],
        sent: [MessageHeader] = [],
        category: @escaping (MessageHeader) -> InboxCategory = { _ in .primary }
    ) -> TodayDigest {
        TodayDigestBuilder.build(
            inbox: [(source, inbox)],
            sent: [(source, sent)],
            myAddresses: ["alex@example.org"],
            now: now,
            classify: { header, _ in category(header) }
        )
    }

    private static let maya = Correspondent(name: "Maya Okafor", email: "maya@northwind.example")
    private static let daniel = Correspondent(name: "Daniel Reyes", email: "daniel@example.com")

    @Test("unanswered mail from people waits on you, newest first")
    func waitingOnYou() {
        let digest = Self.build(inbox: [
            Self.header("old", from: Self.maya, hoursAgo: 30),
            Self.header("new", from: Self.daniel, hoursAgo: 2),
            Self.header("answered", from: Self.maya, hoursAgo: 1, isAnswered: true),
        ])
        #expect(digest.waitingOnYou.map(\.header.id) == ["new", "old"])
        #expect(digest.waitingOnYouCount == 2)
    }

    @Test("newsletters and receipts never wait on you, but count as unread updates")
    func updatesAreSeparate() {
        let digest = Self.build(
            inbox: [
                Self.header("person", from: Self.maya, hoursAgo: 1),
                Self.header("receipt", from: Correspondent(email: "billing@shop.example"), hoursAgo: 1),
                Self.header("readReceipt", from: Correspondent(email: "billing@shop.example"), hoursAgo: 1, isRead: true),
            ],
            category: { $0.id == "person" ? .primary : .transactions }
        )
        #expect(digest.waitingOnYou.map(\.header.id) == ["person"])
        #expect(digest.unreadUpdatesCount == 1)
    }

    @Test("only the newest message of a conversation counts; my own last word clears it")
    func latestPerConversation() {
        let digest = Self.build(
            inbox: [
                Self.header("m1", thread: "t", from: Self.maya, hoursAgo: 5),
                Self.header("m2", thread: "t", from: Self.maya, hoursAgo: 3),
                Self.header("d1", thread: "u", from: Self.daniel, hoursAgo: 4),
            ],
            sent: [Self.header("s1", thread: "u", folder: "sent", from: Self.me, to: [Self.daniel], hoursAgo: 2)]
        )
        #expect(digest.waitingOnYou.map(\.header.id) == ["m2"])
    }

    @Test("on IMAP my reply clears the conversation by In-Reply-To or References, not thread ID")
    func imapReplyByReference() {
        // IMAP threads per folder, so Inbox and Sent never share a thread ID.
        let digest = Self.build(
            inbox: [
                Self.header("a1", thread: "<a1@x>", from: Self.maya, hoursAgo: 6, messageID: "<a1@x>"),
                Self.header("a2", thread: "<a1@x>", from: Self.maya, hoursAgo: 5, messageID: "<a2@x>"),
                Self.header("b1", thread: "<b1@x>", from: Self.daniel, hoursAgo: 4, messageID: "<b1@x>"),
                Self.header("c1", thread: "<c1@x>", from: Self.daniel, hoursAgo: 1, messageID: "<c1@x>"),
            ],
            sent: [
                // Answers an older message of thread a, after its newest one.
                Self.header("r1", thread: "<r1@x>", folder: "sent", from: Self.me, to: [Self.maya],
                            hoursAgo: 2, messageID: "<r1@x>", inReplyTo: "<a1@x>"),
                // A reply sent before c1 arrived does not answer c1.
                Self.header("r2", thread: "<r2@x>", folder: "sent", from: Self.me, to: [Self.daniel],
                            hoursAgo: 3, messageID: "<r2@x>", references: ["<b1@x>", "<c1@x>"]),
            ]
        )
        #expect(digest.waitingOnYou.map(\.header.id) == ["c1"])
    }

    @Test("an Inbox copy of a message I sent is mine, not waiting on me")
    func inboxCopyOfSentMail() {
        let alias = Correspondent(name: "Alex", email: "alex.alias@example.org")
        let digest = Self.build(
            inbox: [Self.header("copy", from: alias, to: [Self.maya], hoursAgo: 2, messageID: "<s@x>")],
            sent: [Self.header("s", folder: "sent", from: alias, to: [Self.maya], hoursAgo: 2, messageID: "<s@x>")]
        )
        #expect(digest.waitingOnYou.isEmpty)
    }

    @Test("my sent mail waits on others until a reply arrives, after a grace day")
    func youreWaitingOn() {
        let digest = Self.build(
            inbox: [
                // A reply linked only by In-Reply-To still counts as an answer.
                Self.header("reply", thread: "other", from: Self.daniel, hoursAgo: 10, inReplyTo: "<s2@x>"),
            ],
            sent: [
                Self.header("s1", folder: "sent", from: Self.me, to: [Self.maya], hoursAgo: 48, messageID: "<s1@x>"),
                Self.header("s2", folder: "sent", from: Self.me, to: [Self.daniel], hoursAgo: 40, messageID: "<s2@x>"),
                Self.header("fresh", folder: "sent", from: Self.me, to: [Self.maya], hoursAgo: 3),
                Self.header("toSelf", folder: "sent", from: Self.me, to: [Self.me], hoursAgo: 48),
            ]
        )
        #expect(digest.youreWaitingOn.map(\.header.id) == ["s1"])
        #expect(digest.youreWaitingOn.first?.person == Self.maya)
        #expect(digest.youreWaitingOnCount == 1)
    }

    @Test("mail older than the window and my own inbox copies are ignored")
    func windowAndSelf() {
        let digest = Self.build(inbox: [
            Self.header("ancient", from: Self.maya, hoursAgo: 24 * 30),
            Self.header("mine", from: Self.me, hoursAgo: 1),
        ])
        #expect(digest.waitingOnYou.isEmpty)
        #expect(digest.isEmpty)
    }

    @Test("lists are capped but counts are not")
    func caps() {
        let inbox = (0 ..< 9).map { Self.header("p\($0)", from: Self.maya, hoursAgo: Double($0) + 1) }
        let digest = Self.build(inbox: inbox)
        #expect(digest.waitingOnYou.count == TodayDigestBuilder.rowLimit)
        #expect(digest.waitingOnYouCount == 9)
    }

    @Test("greeting follows the hour and uses the first name")
    func greeting() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour))!
        }
        #expect(TodayGreeting.period(at: at(7), calendar: calendar) == .morning)
        #expect(TodayGreeting.period(at: at(13), calendar: calendar) == .afternoon)
        #expect(TodayGreeting.period(at: at(20), calendar: calendar) == .evening)
        #expect(TodayGreeting.period(at: at(2), calendar: calendar) == .evening)
        #expect(TodayGreeting.firstName(from: "Alex Chen") == "Alex")
        #expect(TodayGreeting.firstName(from: "alex@example.org") == nil)
        #expect(TodayGreeting.firstName(from: "  ") == nil)
    }
}
