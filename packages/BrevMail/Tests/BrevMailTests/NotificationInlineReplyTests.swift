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

@Suite("Notification inline reply")
struct NotificationInlineReplyTests {
    @Test("builds a threaded reply draft through the compose policy")
    func buildsThreadedReplyDraft() throws {
        let draft = try #require(NotificationInlineReplyComposer.draft(
            id: "draft-1",
            userText: "  Thanks <Henrik> & see you soon.  ",
            header: Self.header,
            accountEmail: "henrik@example.org",
            signatureBody: "Regards,\nHenrik",
            securityMode: .signAndEncrypt
        ))

        #expect(draft.id == "draft-1")
        #expect(draft.to.map(\.email) == ["maja@example.org"])
        #expect(draft.subject == "Re: Standup notes")
        #expect(draft.htmlBody.contains("Thanks &lt;Henrik&gt; &amp; see you soon."))
        #expect(draft.htmlBody.contains("<div class=\"signature\">Regards,<br>Henrik</div>"))
        #expect(draft.inReplyToMessageID == "message-1@example.org")
        #expect(draft.securityMode == .signAndEncrypt)
    }

    @Test("rejects blank replies and replies without a recipient")
    func rejectsUnsuitableReplies() {
        #expect(NotificationInlineReplyComposer.draft(
            id: "draft-1",
            userText: "  \n ",
            header: Self.header,
            accountEmail: "henrik@example.org",
            signatureBody: nil,
            securityMode: .none
        ) == nil)

        let messageFromSelf = MessageHeader(
            id: "msg-self",
            threadID: "thread-self",
            folderID: "inbox",
            from: .init(name: "Henrik", email: "henrik@example.org"),
            subject: "Note to self",
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )
        #expect(NotificationInlineReplyComposer.draft(
            id: "draft-2",
            userText: "Reply",
            header: messageFromSelf,
            accountEmail: "henrik@example.org",
            signatureBody: nil,
            securityMode: .none
        ) == nil)
    }

    @Test("inline reply is withheld while Undo Send requires a cancellation window")
    func inlineReplyAvailabilityRespectsUndoSend() {
        #expect(NotificationInlineReplyAvailabilityPolicy.allows(undoSendDelaySeconds: 0))
        #expect(!NotificationInlineReplyAvailabilityPolicy.allows(undoSendDelaySeconds: 5))
        #expect(!NotificationInlineReplyAvailabilityPolicy.allows(undoSendDelaySeconds: -1))
    }

    @Test("saves before sending and sends the persisted draft")
    func savesBeforeSending() async {
        let recorder = PipelineRecorder()
        let draft = Draft(id: "draft-1", subject: "Subject", htmlBody: "Reply")

        let outcome = await NotificationInlineReplyPipeline.deliver(
            draft: draft,
            save: { draft in
                await recorder.record("save:\(draft.id)")
                var saved = draft
                saved.remoteID = "remote-1"
                return saved
            },
            send: { draft in
                await recorder.record("send:\(draft.remoteID ?? "nil")")
            }
        )

        #expect(outcome == .sent)
        #expect(await recorder.events == ["save:draft-1", "send:remote-1"])
    }

    @Test("reports whether a failed reply was preserved as a draft")
    func distinguishesSaveAndSendFailures() async {
        let draft = Draft(id: "draft-1")

        let saveFailure = await NotificationInlineReplyPipeline.deliver(
            draft: draft,
            save: { _ in throw TestFailure() },
            send: { _ in Issue.record("send must not run after save fails") }
        )
        #expect(saveFailure == .failed(draftWasSaved: false))

        let sendFailure = await NotificationInlineReplyPipeline.deliver(
            draft: draft,
            save: { $0 },
            send: { _ in throw TestFailure() }
        )
        #expect(sendFailure == .failed(draftWasSaved: true))
    }

    @Test("failure payload reopens the exact message without exposing reply content")
    func failurePayloadIsRoutableAndPrivate() {
        let route = NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1",
            sourceID: MailSourceID(accountID: "acct-1", mailboxID: "mailbox-1")
        )

        let saved = NotificationReplyFailurePolicy.payload(
            route: route,
            draftWasSaved: true
        )
        #expect(saved.title == "Reply not sent")
        #expect(saved.body == "Your reply is saved in Drafts. Open Brev to try again.")
        #expect(NotificationRoutingPolicy.route(from: saved.userInfo) == route)
        #expect(saved.userInfo.keys.sorted() == [
            "accountID",
            "folderID",
            "messageID",
            "sourceAccountID",
            "sourceMailboxID",
        ])

        let unsaved = NotificationReplyFailurePolicy.payload(
            route: route,
            draftWasSaved: false
        )
        #expect(unsaved.body == "Open Brev to review the message and try again.")
    }

    private static let header = MessageHeader(
        id: "msg-1",
        threadID: "thread-1",
        folderID: "inbox",
        from: .init(name: "Maja Holm", email: "maja@example.org"),
        subject: "Standup notes",
        snippet: "Can we pull the UI polish task?",
        date: Date(timeIntervalSince1970: 0),
        messageID: "message-1@example.org"
    )
}

private actor PipelineRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private struct TestFailure: Error {}
