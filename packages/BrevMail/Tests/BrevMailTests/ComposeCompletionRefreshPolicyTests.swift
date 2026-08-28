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

@Suite("ComposeCompletionRefreshPolicy")
struct ComposeCompletionRefreshPolicyTests {
    @Test("saving a draft shows a saved confirmation toast")
    func savingDraftShowsSavedConfirmation() {
        #expect(ComposeCompletionPresentation.feedback(
            for: .savedDraft(Self.makeDraft(id: "d1"))
        ) == .toast(message: "Draft saved.", tone: .success))
        #expect(ComposeCompletionPresentation.status(
            for: .savedDraft(Self.makeDraft(id: "d1"))
        ) == nil)
    }

    @Test("saving a draft refreshes the Drafts folder")
    func savingDraftRefreshesDraftsFolder() {
        let events = ComposeCompletionRefreshPolicy.events(
            for: .savedDraft(Self.makeDraft(id: "d1")),
            folders: Self.folders
        )

        #expect(events == [.folderRefreshed(folderID: "drafts")])
    }

    @Test("sending a new message refreshes Drafts and Sent")
    func sendingNewMessageRefreshesDraftsAndSent() {
        let events = ComposeCompletionRefreshPolicy.events(
            for: .sentMessage(
                draft: Self.makeDraft(id: "d2"),
                result: SendResult(sentMessageID: "sent-d2"),
                relatedHeader: nil
            ),
            folders: Self.folders
        )

        #expect(events == [
            .folderRefreshed(folderID: "drafts"),
            .folderRefreshed(folderID: "sent")
        ])
    }

    @Test("sending a reply refreshes the source row after Drafts and Sent")
    func sendingReplyRefreshesSourceRowAfterDraftsAndSent() {
        let events = ComposeCompletionRefreshPolicy.events(
            for: .sentMessage(
                draft: Self.makeDraft(id: "d3"),
                result: SendResult(sentMessageID: "sent-d3"),
                relatedHeader: Self.makeHeader(id: "source-1", folderID: "inbox")
            ),
            folders: Self.folders
        )

        #expect(events == [
            .folderRefreshed(folderID: "drafts"),
            .folderRefreshed(folderID: "sent"),
            .messagesUpdated(folderID: "inbox", messageIDs: ["source-1"])
        ])
    }

    private static let folders = [
        Folder(id: "inbox", name: "Inbox", role: .inbox),
        Folder(id: "drafts", name: "Drafts", role: .drafts),
        Folder(id: "sent", name: "Sent", role: .sent)
    ]

    private static func makeDraft(id: Draft.ID) -> Draft {
        Draft(
            id: id,
            remoteID: "remote-\(id)",
            to: [Correspondent(email: "ada@example.org")],
            subject: "Hello",
            htmlBody: "Body"
        )
    }

    @Test("sending without schedule returns no completion status")
    func sendingWithoutScheduleReturnsNoStatus() {
        let draft = Draft(id: "local-1", subject: "Hi", htmlBody: "Body")
        let result = SendResult(sentMessageID: "msg-1", scheduledFor: nil)
        let completion = ComposeCompletion.sentMessage(
            draft: draft,
            result: result,
            relatedHeader: nil
        )
        #expect(ComposeCompletionPresentation.status(for: completion) == nil)
    }

    @Test("sending with Sent copy warning shows warning status")
    func sendingWithSentCopyWarningShowsWarningStatus() throws {
        let draft = Draft(id: "local-1", subject: "Hi", htmlBody: "Body")
        let result = SendResult(
            sentMessageID: "msg-1",
            warnings: [.sentCopyAppendFailed]
        )
        let completion = ComposeCompletion.sentMessage(
            draft: draft,
            result: result,
            relatedHeader: nil
        )

        let status = try #require(ComposeCompletionPresentation.status(for: completion))

        #expect(status.message == "Message sent, but Brev couldn't save a copy to Sent.")
        #expect(status.tone == .warning)
    }

    @Test("sending with remote draft cleanup warning shows warning status")
    func sendingWithRemoteDraftCleanupWarningShowsWarningStatus() throws {
        let draft = Draft(id: "local-1", subject: "Hi", htmlBody: "Body")
        let result = SendResult(
            sentMessageID: "msg-1",
            warnings: [.remoteDraftCleanupFailed]
        )
        let completion = ComposeCompletion.sentMessage(
            draft: draft,
            result: result,
            relatedHeader: nil
        )

        let status = try #require(ComposeCompletionPresentation.status(for: completion))

        #expect(status.message == "Message sent, but Brev couldn't remove the saved draft.")
        #expect(status.tone == .warning)
    }

    @Test("queued send warning shows Outbox status")
    func queuedSendWarningShowsOutboxStatus() throws {
        let draft = Draft(id: "local-1", subject: "Hi", htmlBody: "Body")
        let result = SendResult(warnings: [.queuedForRetry])
        let completion = ComposeCompletion.sentMessage(
            draft: draft,
            result: result,
            relatedHeader: nil
        )

        let status = try #require(ComposeCompletionPresentation.status(for: completion))

        #expect(status.message == "Message queued in Outbox and will retry when the account is online.")
        #expect(status.tone == .warning)
    }

    @Test("sending with schedule shows scheduled confirmation toast")
    func sendingWithScheduleShowsScheduledConfirmation() throws {
        let draft = Draft(id: "local-1", subject: "Hi", htmlBody: "Body")
        let scheduledFor = Date(timeIntervalSince1970: 1_900_000_000)
        let result = SendResult(sentMessageID: "msg-1", scheduledFor: scheduledFor)
        let completion = ComposeCompletion.sentMessage(
            draft: draft,
            result: result,
            relatedHeader: nil
        )
        let feedback = try #require(ComposeCompletionPresentation.feedback(for: completion))
        guard case .toast(let message, let tone) = feedback else {
            Issue.record("Expected toast feedback")
            return
        }
        #expect(message.contains("scheduled"))
        #expect(tone == .success)
        #expect(ComposeCompletionPresentation.status(for: completion) == nil)
    }

    private static func makeHeader(
        id: MessageHeader.ID,
        folderID: Folder.ID
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
