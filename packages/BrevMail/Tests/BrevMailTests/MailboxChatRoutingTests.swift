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
import Testing

@Suite("Mailbox chat routing")
struct MailboxChatRoutingTests {
    @Test("ordinary mailbox questions route to answer")
    func ordinaryMailboxQuestionsRouteToAnswer() {
        #expect(MailboxChatIntentRouter.classify("what did jane say about invoices?") == .answer)
    }

    @Test("delete requests route to action")
    func deleteRequestsRouteToAction() {
        #expect(MailboxChatIntentRouter.classify("delete all mail from a@b.com") == .action)
    }

    @Test("planner action verbs route to action")
    func plannerActionVerbsRouteToAction() {
        let actionRequests = [
            "remove all mail from a@b.com",
            "trash all mail from a@b.com",
            "move all mail from a@b.com to receipts",
            "archive all mail from a@b.com",
            "mark all mail from a@b.com as read",
            "mark all mail from a@b.com as unread",
            "flag all mail from a@b.com",
            "unflag all mail from a@b.com",
        ]

        for request in actionRequests {
            #expect(MailboxChatIntentRouter.classify(request) == .action)
        }
    }
}
