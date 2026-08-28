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

@Suite("Mailbox chat action flow")
struct MailboxChatActionFlowTests {
    private let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
    private let sourceScope = MailboxActionAgentSourceScope(
        sourceID: MailSourceID(accountID: "account-1", mailboxID: "mailbox-1"),
        accountName: "Work",
        mailboxName: "Primary",
        mailboxAddress: "me@example.com"
    )
    private let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

    @Test("action route produces a review turn from cache-only sender search")
    @MainActor
    func actionRouteProducesAReviewTurnFromCacheOnlySenderSearch() async throws {
        let recorder = SearchRecorder(results: [
            Self.header(id: "message-1", from: "ada@example.com", folderID: "inbox", subject: "Invoice")
        ])
        let executionSpy = ActionExecutionSpy()
        let controller = MailboxChatController(
            scope: .sender(email: "ada@example.com"),
            sourceID: sourceID,
            aiBackend: nil,
            actionFolders: [inbox],
            focusedFolder: nil,
            actionSourceScope: sourceScope,
            executeAction: { plan in
                await executionSpy.execute(plan)
            },
            search: makeSearch(recorder)
        )

        await controller.send(userText: "delete all mail from ada@example.com")

        let query = try #require(await recorder.lastQuery)
        #expect(query == SearchQuery(from: "ada@example.com", execution: .cacheOnly))
        #expect(await recorder.lastSourceID == sourceID)
        #expect(await executionSpy.callCount == 0)

        #expect(controller.turns.count == 2)
        #expect(controller.turns[0] == MailboxChatTurnKind.user("delete all mail from ada@example.com"))

        guard case .actionReview(let plan, let providerLabel) = controller.turns[1] else {
            Issue.record("Expected an action review turn")
            return
        }

        #expect(providerLabel == MailboxChatController.localActionProviderLabel)
        #expect(plan.senderEmail == "ada@example.com")
        #expect(plan.searchQuery == SearchQuery(from: "ada@example.com", execution: .cacheOnly))
        #expect(plan.matchingMessageIDs == ["message-1"])
        #expect(plan.confirmationChallenge.requiredPhrase == "DELETE 1")
    }

    @Test("exact confirm phrase is required before executing the planned action")
    @MainActor
    func exactConfirmPhraseIsRequiredBeforeExecutingThePlannedAction() async throws {
        let recorder = SearchRecorder(results: [
            Self.header(id: "message-1", from: "ada@example.com", folderID: "inbox", subject: "Invoice")
        ])
        let executionSpy = ActionExecutionSpy()
        let controller = MailboxChatController(
            scope: .sender(email: "ada@example.com"),
            sourceID: sourceID,
            aiBackend: nil,
            actionFolders: [inbox],
            focusedFolder: nil,
            actionSourceScope: sourceScope,
            executeAction: { plan in
                await executionSpy.execute(plan)
            },
            search: makeSearch(recorder)
        )

        await controller.send(userText: "delete all mail from ada@example.com")

        let plan = try #require(actionReviewPlan(in: controller.turns))

        await controller.confirmAction(planID: plan.id, phrase: "delete 1")
        #expect(await executionSpy.callCount == 0)
        #expect(controller.turns.count == 2)

        await controller.confirmAction(
            planID: plan.id,
            phrase: plan.confirmationChallenge.requiredPhrase
        )

        #expect(await executionSpy.callCount == 1)
        #expect(await executionSpy.lastPlanID == plan.id)
        #expect(controller.turns.last == MailboxChatTurnKind.clarification(
            text: "Deleted 1 message from ada@example.com.",
            providerLabel: MailboxChatProviderLabelPolicy.actionPlanner()
        ))
    }

    @Test("successful action confirmation consumes the review card")
    @MainActor
    func successfulActionConfirmationConsumesTheReviewCard() async throws {
        let recorder = SearchRecorder(results: [
            Self.header(id: "message-1", from: "ada@example.com", folderID: "inbox", subject: "Invoice")
        ])
        let executionSpy = ActionExecutionSpy()
        let controller = MailboxChatController(
            scope: .sender(email: "ada@example.com"),
            sourceID: sourceID,
            aiBackend: nil,
            actionFolders: [inbox],
            focusedFolder: nil,
            actionSourceScope: sourceScope,
            executeAction: { plan in
                await executionSpy.execute(plan)
            },
            search: makeSearch(recorder)
        )

        await controller.send(userText: "delete all mail from ada@example.com")

        let plan = try #require(actionReviewPlan(in: controller.turns))
        await controller.confirmAction(
            planID: plan.id,
            phrase: plan.confirmationChallenge.requiredPhrase
        )

        #expect(await executionSpy.callCount == 1)
        #expect(actionReviewPlan(in: controller.turns) == nil)
        #expect(controller.turns == [
            .user("delete all mail from ada@example.com"),
            .clarification(
                text: "Deleted 1 message from ada@example.com.",
                providerLabel: MailboxChatProviderLabelPolicy.actionPlanner()
            )
        ])

        await controller.confirmAction(
            planID: plan.id,
            phrase: plan.confirmationChallenge.requiredPhrase
        )

        #expect(await executionSpy.callCount == 1)
        #expect(controller.turns == [
            .user("delete all mail from ada@example.com"),
            .clarification(
                text: "Deleted 1 message from ada@example.com.",
                providerLabel: MailboxChatProviderLabelPolicy.actionPlanner()
            )
        ])
    }

    @Test("duplicate confirms are ignored while the first confirm is still running")
    @MainActor
    func duplicateConfirmsAreIgnoredWhileTheFirstConfirmIsStillRunning() async throws {
        let recorder = SearchRecorder(results: [
            Self.header(id: "message-1", from: "ada@example.com", folderID: "inbox", subject: "Invoice")
        ])
        let executionSpy = SlowActionExecutionSpy()
        let controller = MailboxChatController(
            scope: .sender(email: "ada@example.com"),
            sourceID: sourceID,
            aiBackend: nil,
            actionFolders: [inbox],
            focusedFolder: nil,
            actionSourceScope: sourceScope,
            executeAction: { plan in
                try await executionSpy.execute(plan)
            },
            search: makeSearch(recorder)
        )

        await controller.send(userText: "delete all mail from ada@example.com")

        let plan = try #require(actionReviewPlan(in: controller.turns))
        let confirmTask = Task {
            await controller.confirmAction(
                planID: plan.id,
                phrase: plan.confirmationChallenge.requiredPhrase
            )
        }

        await executionSpy.waitForFirstCall()

        let duplicateConfirmTask = Task {
            await controller.confirmAction(
                planID: plan.id,
                phrase: plan.confirmationChallenge.requiredPhrase
            )
        }

        await duplicateConfirmTask.value
        #expect(await executionSpy.callCount == 1)

        await executionSpy.finishFirstCall()
        await confirmTask.value

        #expect(await executionSpy.callCount == 1)
        #expect(controller.turns == [
            .user("delete all mail from ada@example.com"),
            .clarification(
                text: "Deleted 1 message from ada@example.com.",
                providerLabel: MailboxChatProviderLabelPolicy.actionPlanner()
            )
        ])
    }

    private func actionReviewPlan(
        in turns: [MailboxChatTurnKind]
    ) -> MailboxActionAgentPlan? {
        for turn in turns {
            if case .actionReview(let plan, _) = turn {
                return plan
            }
        }
        return nil
    }

    private func makeSearch(_ recorder: SearchRecorder) -> MailboxChatController.Search {
        { query, sourceID in
            try await recorder.search(query: query, sourceID: sourceID)
        }
    }

    private static func header(
        id: String,
        from: String,
        folderID: String,
        subject: String
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-1",
            folderID: folderID,
            from: Correspondent(name: "Ada", email: from),
            subject: subject,
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 86400)
        )
    }
}

private actor SearchRecorder {
    private(set) var lastQuery: SearchQuery?
    private(set) var lastSourceID: MailSourceID?

    let results: [MessageHeader]

    init(results: [MessageHeader]) {
        self.results = results
    }

    func search(query: SearchQuery, sourceID: MailSourceID?) async throws -> [MessageHeader] {
        lastQuery = query
        lastSourceID = sourceID
        return results
    }
}

private actor ActionExecutionSpy {
    private(set) var callCount = 0
    private(set) var lastPlanID: UUID?

    func execute(_ plan: MailboxActionAgentPlan) -> String {
        callCount += 1
        lastPlanID = plan.id
        return MailboxActionAgentCompletionPresentation.message(for: plan)
    }
}

private actor SlowActionExecutionSpy {
    private(set) var callCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func execute(_ plan: MailboxActionAgentPlan) async throws -> String {
        _ = plan
        callCount += 1
        notifyWaiters()
        if callCount > 1 {
            return "Deleted 1 message from ada@example.com."
        }
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
        return "Deleted 1 message from ada@example.com."
    }

    func waitForFirstCall() async {
        if callCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finishFirstCall() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    private func notifyWaiters() {
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}
