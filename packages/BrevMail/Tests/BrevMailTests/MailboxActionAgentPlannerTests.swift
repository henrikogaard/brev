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

@Suite("MailboxActionAgentPlanner")
struct MailboxActionAgentPlannerTests {
    private let fixedPlanID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let fixedMutationID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let fixedDate = Date(timeIntervalSince1970: 1_779_964_800)
    private let fixedNow = Date(timeIntervalSince1970: 1_779_964_800)
    private let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
    private let sourceScope = MailboxActionAgentSourceScope(
        sourceID: MailSourceID(accountID: "account-1", mailboxID: "mailbox-1"),
        accountName: "Work",
        mailboxName: "Primary",
        mailboxAddress: "me@example.com"
    )

    @Test("delete request from sender creates confirmation-gated plan with exact matches")
    func deleteRequestFromSenderCreatesConfirmationGatedPlan() {
        let headers = [
            Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
            Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert"),
            Self.header(id: "m-3", from: "INVOICES@example.com", subject: "Invoice 2")
        ]
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "delete all mails from sender invoices@example.com",
            headers: headers,
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.id == fixedPlanID)
        #expect(plan.senderEmail == "invoices@example.com")
        #expect(plan.operation == .delete)
        #expect(plan.isDestructive)
        #expect(plan.requiresConfirmation)
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.confirmationChallenge.prompt == "Delete 2 messages from invoices@example.com?")
        #expect(plan.authorization(with: nil) == .requiresConfirmation(plan.confirmationChallenge))
        #expect(plan.authorization(with: .init(planID: fixedPlanID, phrase: "DELETE 2")) == .authorized)
    }

    @Test("move request from sender resolves target folder by name")
    func moveRequestFromSenderResolvesTargetFolderByName() {
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let headers = [
            Self.header(id: "m-1", from: "support@example.com", subject: "Ticket"),
            Self.header(id: "m-2", from: "friend@example.com", subject: "Hello")
        ]
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "move all mails from sender support@example.com to Receipts",
            headers: headers,
            folders: [receipts],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.operation == .move(to: receipts))
        #expect(!plan.isDestructive)
        #expect(plan.requiresConfirmation)
        #expect(plan.matchingMessageIDs == ["m-1"])
        #expect(plan.confirmationChallenge.prompt == "Move 1 message from support@example.com to Receipts?")
        #expect(plan.authorization(with: .init(planID: fixedPlanID, phrase: "MOVE 1")) == .authorized)
    }

    @Test("move request ignores a generic folder prefix before target name")
    func moveRequestIgnoresGenericFolderPrefixBeforeTargetName() {
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "move all mails from sender support@example.com to folder Receipts",
            headers: [Self.header(id: "m-1", from: "support@example.com", subject: "Ticket")],
            folders: [receipts],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.operation == .move(to: receipts))
        #expect(plan.confirmationChallenge.prompt == "Move 1 message from support@example.com to Receipts?")
    }

    @Test("move request can use the focused folder as target")
    func moveRequestCanUseFocusedFolderAsTarget() {
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "move all mails from sender sss@ssss.co to this folder here",
            headers: [Self.header(id: "m-1", from: "sss@ssss.co", subject: "Receipt")],
            folders: [receipts],
            focusedFolder: receipts
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.operation == .move(to: receipts))
        #expect(plan.confirmationChallenge.prompt == "Move 1 message from sss@ssss.co to Receipts?")
    }

    @Test("mark-read request from sender creates a confirmation-gated plan")
    func markReadRequestFromSenderCreatesConfirmationGatedPlan() {
        let headers = [
            Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isRead: false),
            Self.header(id: "m-2", from: "friend@example.com", subject: "Hello", isRead: false),
            Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2", isRead: false)
        ]
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "mark all mails from sender alerts@example.com as read",
            headers: headers,
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(!plan.isDestructive)
        #expect(plan.requiresConfirmation)
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.confirmationChallenge.prompt == "Mark 2 messages from alerts@example.com as read?")
        #expect(plan.authorization(with: .init(planID: fixedPlanID, phrase: "MARK READ 2")) == .authorized)
        #expect(presentation.title == "Confirm Mark Read")
        #expect(presentation.message == "There are 2 messages from alerts@example.com. Mark them as read?")
        #expect(presentation.confirmButtonTitle == "Mark Read 2 Messages")
        #expect(presentation.requiredPhrase == "MARK READ 2")
        #expect(presentation.warningMessage == nil)
    }

    @Test("mark-unread request from sender creates a confirmation-gated plan")
    func markUnreadRequestFromSenderCreatesConfirmationGatedPlan() {
        let headers = [
            Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isRead: true),
            Self.header(id: "m-2", from: "friend@example.com", subject: "Hello", isRead: true),
            Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2", isRead: true)
        ]
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "mark all mails from sender alerts@example.com as unread",
            headers: headers,
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(!plan.isDestructive)
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.confirmationChallenge.prompt == "Mark 2 messages from alerts@example.com as unread?")
        #expect(plan.authorization(with: .init(planID: fixedPlanID, phrase: "MARK UNREAD 2")) == .authorized)
    }

    @Test("flag request from sender creates a confirmation-gated plan")
    func flagRequestFromSenderCreatesConfirmationGatedPlan() {
        let headers = [
            Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isFlagged: false),
            Self.header(id: "m-2", from: "friend@example.com", subject: "Hello", isFlagged: false),
            Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2", isFlagged: false)
        ]
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "flag all mails from sender alerts@example.com",
            headers: headers,
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(!plan.isDestructive)
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.confirmationChallenge.prompt == "Flag 2 messages from alerts@example.com?")
        #expect(plan.authorization(with: .init(planID: fixedPlanID, phrase: "FLAG 2")) == .authorized)
        #expect(presentation.title == "Confirm Flag")
        #expect(presentation.message == "There are 2 messages from alerts@example.com. Flag them?")
        #expect(presentation.confirmButtonTitle == "Flag 2 Messages")
        #expect(presentation.requiredPhrase == "FLAG 2")
        #expect(presentation.warningMessage == nil)
    }

    @Test("unflag request from sender creates a confirmation-gated plan")
    func unflagRequestFromSenderCreatesConfirmationGatedPlan() {
        let headers = [
            Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isFlagged: true),
            Self.header(id: "m-2", from: "friend@example.com", subject: "Hello", isFlagged: true),
            Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2", isFlagged: true)
        ]
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "unflag all mails from sender alerts@example.com",
            headers: headers,
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(!plan.isDestructive)
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.confirmationChallenge.prompt == "Unflag 2 messages from alerts@example.com?")
        #expect(plan.authorization(with: .init(planID: fixedPlanID, phrase: "UNFLAG 2")) == .authorized)
    }

    @Test("archive request from sender creates a confirmation-gated plan")
    func archiveRequestFromSenderCreatesConfirmationGatedPlan() {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let headers = [
            Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1"),
            Self.header(id: "m-2", from: "friend@example.com", subject: "Hello"),
            Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2")
        ]
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "archive all mails from sender alerts@example.com",
            headers: headers,
            folders: [archive],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(!plan.isDestructive)
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.confirmationChallenge.prompt == "Archive 2 messages from alerts@example.com?")
        #expect(plan.authorization(with: .init(planID: fixedPlanID, phrase: "ARCHIVE 2")) == .authorized)
        #expect(presentation.title == "Confirm Archive")
        #expect(presentation.message == "There are 2 messages from alerts@example.com. Archive them?")
        #expect(presentation.confirmButtonTitle == "Archive 2 Messages")
        #expect(presentation.requiredPhrase == "ARCHIVE 2")
        #expect(presentation.warningMessage == nil)
    }

    @Test("archive request without archive folder asks for clarification")
    func archiveRequestWithoutArchiveFolderAsksForClarification() {
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "archive all mails from sender alerts@example.com",
            headers: [],
            folders: [],
            focusedFolder: nil
        )

        #expect(result == .clarificationRequired(.unknownFolder("Archive")))
    }

    @Test("missing sender asks for clarification instead of planning")
    func missingSenderAsksForClarificationInsteadOfPlanning() {
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "delete all newsletters",
            headers: [],
            folders: [],
            focusedFolder: nil
        )

        #expect(result == .clarificationRequired(.missingSender))
    }

    @Test("move request without resolvable target folder asks for clarification")
    func moveRequestWithoutResolvableTargetFolderAsksForClarification() {
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "move all mails from sender support@example.com to Receipts",
            headers: [],
            folders: [],
            focusedFolder: nil
        )

        #expect(result == .clarificationRequired(.unknownFolder("Receipts")))
    }

    @Test("wrong confirmation token does not authorize execution")
    func wrongConfirmationTokenDoesNotAuthorizeExecution() {
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "delete all mails from sender invoices@example.com",
            headers: [Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice")],
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        let wrongPlanID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        #expect(plan
            .authorization(with: .init(planID: wrongPlanID, phrase: "DELETE 1")) ==
            .requiresConfirmation(plan.confirmationChallenge))
        #expect(plan
            .authorization(with: .init(planID: fixedPlanID, phrase: "delete 1")) ==
            .requiresConfirmation(plan.confirmationChallenge))
    }

    @Test("executor refuses unconfirmed plans without enqueuing mutations")
    func executorRefusesUnconfirmedPlansWithoutEnqueuingMutations() async throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice")]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: nil,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .requiresConfirmation(plan.confirmationChallenge))
        #expect(try await queue.pending().isEmpty)
    }

    @Test("confirmed delete plan enqueues source-scoped delete mutation")
    func confirmedDeletePlanEnqueuesSourceScopedDeleteMutation() async throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [
                Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
                Self.header(id: "m-2", from: "invoices@example.com", subject: "Invoice 2")
            ]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )
        let confirmation = MailboxActionAgentConfirmation(
            planID: fixedPlanID,
            phrase: "DELETE 2"
        )
        let expectedMutation = PendingMutation(
            id: fixedMutationID,
            kind: .delete,
            sourceID: sourceID,
            messageIDs: ["m-1", "m-2"],
            createdAt: fixedDate
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: confirmation,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .enqueued(expectedMutation))
        #expect(try await queue.pending() == [expectedMutation])
    }

    @Test("confirmed move plan enqueues source-scoped move mutation")
    func confirmedMovePlanEnqueuesSourceScopedMoveMutation() async throws {
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let plan = try #require(Self.planned(
            request: "move all mails from sender support@example.com to Receipts",
            headers: [Self.header(id: "m-1", from: "support@example.com", subject: "Ticket")],
            folders: [receipts]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )
        let confirmation = MailboxActionAgentConfirmation(
            planID: fixedPlanID,
            phrase: "MOVE 1"
        )
        let expectedMutation = PendingMutation(
            id: fixedMutationID,
            kind: .move(folderID: receipts.id),
            sourceID: sourceID,
            messageIDs: ["m-1"],
            createdAt: fixedDate
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: confirmation,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .enqueued(expectedMutation))
        #expect(try await queue.pending() == [expectedMutation])
    }

    @Test("confirmed mark-read plan enqueues source-scoped read mutation")
    func confirmedMarkReadPlanEnqueuesSourceScopedReadMutation() async throws {
        let plan = try #require(Self.planned(
            request: "mark all mails from sender alerts@example.com as read",
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isRead: false),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert 2", isRead: false)
            ]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )
        let confirmation = MailboxActionAgentConfirmation(
            planID: fixedPlanID,
            phrase: "MARK READ 2"
        )
        let expectedMutation = PendingMutation(
            id: fixedMutationID,
            kind: .setRead(true),
            sourceID: sourceID,
            messageIDs: ["m-1", "m-2"],
            createdAt: fixedDate
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: confirmation,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .enqueued(expectedMutation))
        #expect(try await queue.pending() == [expectedMutation])
    }

    @Test("confirmed mark-unread plan enqueues source-scoped unread mutation")
    func confirmedMarkUnreadPlanEnqueuesSourceScopedUnreadMutation() async throws {
        let plan = try #require(Self.planned(
            request: "mark all mails from sender alerts@example.com as unread",
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isRead: true),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert 2", isRead: true)
            ]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )
        let confirmation = MailboxActionAgentConfirmation(
            planID: fixedPlanID,
            phrase: "MARK UNREAD 2"
        )
        let expectedMutation = PendingMutation(
            id: fixedMutationID,
            kind: .setRead(false),
            sourceID: sourceID,
            messageIDs: ["m-1", "m-2"],
            createdAt: fixedDate
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: confirmation,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .enqueued(expectedMutation))
        #expect(try await queue.pending() == [expectedMutation])
    }

    @Test("confirmed flag plan enqueues source-scoped flag mutation")
    func confirmedFlagPlanEnqueuesSourceScopedFlagMutation() async throws {
        let plan = try #require(Self.planned(
            request: "flag all mails from sender alerts@example.com",
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isFlagged: false),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert 2", isFlagged: false)
            ]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )
        let confirmation = MailboxActionAgentConfirmation(
            planID: fixedPlanID,
            phrase: "FLAG 2"
        )
        let expectedMutation = PendingMutation(
            id: fixedMutationID,
            kind: .setFlagged(true),
            sourceID: sourceID,
            messageIDs: ["m-1", "m-2"],
            createdAt: fixedDate
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: confirmation,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .enqueued(expectedMutation))
        #expect(try await queue.pending() == [expectedMutation])
    }

    @Test("confirmed unflag plan enqueues source-scoped unflag mutation")
    func confirmedUnflagPlanEnqueuesSourceScopedUnflagMutation() async throws {
        let plan = try #require(Self.planned(
            request: "unflag all mails from sender alerts@example.com",
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isFlagged: true),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert 2", isFlagged: true)
            ]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )
        let confirmation = MailboxActionAgentConfirmation(
            planID: fixedPlanID,
            phrase: "UNFLAG 2"
        )
        let expectedMutation = PendingMutation(
            id: fixedMutationID,
            kind: .setFlagged(false),
            sourceID: sourceID,
            messageIDs: ["m-1", "m-2"],
            createdAt: fixedDate
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: confirmation,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .enqueued(expectedMutation))
        #expect(try await queue.pending() == [expectedMutation])
    }

    @Test("confirmed archive plan enqueues source-scoped move-to-archive mutation")
    func confirmedArchivePlanEnqueuesSourceScopedMoveToArchiveMutation() async throws {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let plan = try #require(Self.planned(
            request: "archive all mails from sender alerts@example.com",
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1"),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert 2")
            ],
            folders: [archive]
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )
        let confirmation = MailboxActionAgentConfirmation(
            planID: fixedPlanID,
            phrase: "ARCHIVE 2"
        )
        let expectedMutation = PendingMutation(
            id: fixedMutationID,
            kind: .move(folderID: archive.id),
            sourceID: sourceID,
            messageIDs: ["m-1", "m-2"],
            createdAt: fixedDate
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: confirmation,
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .enqueued(expectedMutation))
        #expect(try await queue.pending() == [expectedMutation])
    }

    @Test("confirmed zero-match plan does not enqueue an empty mutation")
    func confirmedZeroMatchPlanDoesNotEnqueueEmptyMutation() async throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: []
        ))
        let queue = RecordingMutationQueue()
        let executor = MailboxActionAgentExecutor(
            mutationIDGenerator: { fixedMutationID },
            dateProvider: { fixedDate }
        )

        let result = try await executor.execute(
            plan: plan,
            confirmation: .init(planID: fixedPlanID, phrase: "DELETE 0"),
            sourceID: sourceID,
            queue: queue
        )

        #expect(result == .noMatchingMessages)
        #expect(try await queue.pending().isEmpty)
    }

    @Test("delete confirmation presentation explains count and required phrase")
    func deleteConfirmationPresentationExplainsCountAndRequiredPhrase() throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [
                Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
                Self.header(id: "m-2", from: "invoices@example.com", subject: "Invoice 2")
            ]
        ))

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(presentation.title == "Confirm Delete")
        #expect(presentation.message == "There are 2 messages from invoices@example.com. Delete them?")
        #expect(presentation.confirmButtonTitle == "Delete 2 Messages")
        #expect(presentation.cancelButtonTitle == "Cancel")
        #expect(presentation.requiredPhrase == "DELETE 2")
        #expect(presentation.isDestructive)
        #expect(presentation.canConfirm)
        #expect(presentation.warningMessage == "This cannot be undone from Brev once it reaches the server.")
    }

    @Test("move confirmation presentation explains singular count and target folder")
    func moveConfirmationPresentationExplainsSingularCountAndTargetFolder() throws {
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let plan = try #require(Self.planned(
            request: "move all mails from sender support@example.com to Receipts",
            headers: [Self.header(id: "m-1", from: "support@example.com", subject: "Ticket")],
            folders: [receipts]
        ))

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(presentation.title == "Confirm Move")
        #expect(presentation.message == "There is 1 message from support@example.com. Move it to Receipts?")
        #expect(presentation.confirmButtonTitle == "Move 1 Message")
        #expect(presentation.cancelButtonTitle == "Cancel")
        #expect(presentation.requiredPhrase == "MOVE 1")
        #expect(!presentation.isDestructive)
        #expect(presentation.canConfirm)
        #expect(presentation.warningMessage == nil)
    }

    @Test("planner keeps bounded representative samples for confirmation review")
    func plannerKeepsBoundedRepresentativeSamplesForConfirmationReview() throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [
                Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert"),
                Self.header(id: "m-3", from: "INVOICES@example.com", subject: "Invoice 2"),
                Self.header(id: "m-4", from: "invoices@example.com", subject: "Invoice 3"),
                Self.header(id: "m-5", from: "invoices@example.com", subject: "Invoice 4")
            ]
        ))

        #expect(plan.matchingMessageIDs == ["m-1", "m-3", "m-4", "m-5"])
        #expect(plan.sampleMessages == [
            MailboxActionAgentMessageSample(
                id: "m-1",
                sender: "invoices@example.com",
                subject: "Invoice 1",
                date: Date(timeIntervalSince1970: 1_779_960_600)
            ),
            MailboxActionAgentMessageSample(
                id: "m-3",
                sender: "INVOICES@example.com",
                subject: "Invoice 2",
                date: Date(timeIntervalSince1970: 1_779_960_600)
            ),
            MailboxActionAgentMessageSample(
                id: "m-4",
                sender: "invoices@example.com",
                subject: "Invoice 3",
                date: Date(timeIntervalSince1970: 1_779_960_600)
            )
        ])
    }

    @Test("confirmation presentation includes representative sample rows")
    func confirmationPresentationIncludesRepresentativeSampleRows() throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [
                Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
                Self.header(id: "m-2", from: "invoices@example.com", subject: "Invoice 2")
            ]
        ))

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(presentation.sampleRows == [
            MailboxActionAgentReviewSampleRow(
                title: "Invoice 1",
                subtitle: "invoices@example.com"
            ),
            MailboxActionAgentReviewSampleRow(
                title: "Invoice 2",
                subtitle: "invoices@example.com"
            )
        ])
    }

    @Test("confirmation presentation includes criteria source and matched folders")
    func confirmationPresentationIncludesCriteriaSourceAndMatchedFolders() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [
                Self.header(
                    id: "m-1",
                    from: "invoices@example.com",
                    subject: "Invoice 1",
                    folderID: "inbox"
                ),
                Self.header(
                    id: "m-2",
                    from: "invoices@example.com",
                    subject: "Invoice 2",
                    folderID: "archive"
                )
            ],
            folders: [inbox, archive],
            sourceScope: sourceScope
        ))

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(plan.sourceID == sourceID)
        #expect(plan.matchedFolderNames == ["Inbox", "Archive"])
        #expect(presentation.detailRows == [
            MailboxActionAgentReviewDetailRow(title: "Criteria", value: "From invoices@example.com"),
            MailboxActionAgentReviewDetailRow(title: "Mailbox", value: "Work - Primary (me@example.com)"),
            MailboxActionAgentReviewDetailRow(title: "Matched folders", value: "Inbox, Archive"),
            MailboxActionAgentReviewDetailRow(title: "Action", value: "Delete matched messages")
        ])
    }

    @Test("folder refinement narrows search matches and review criteria")
    func folderRefinementNarrowsSearchMatchesAndReviewCriteria() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com only in Inbox",
            headers: [
                Self.header(
                    id: "m-1",
                    from: "invoices@example.com",
                    subject: "Invoice 1",
                    folderID: "inbox"
                ),
                Self.header(
                    id: "m-2",
                    from: "invoices@example.com",
                    subject: "Invoice 2",
                    folderID: "archive"
                )
            ],
            folders: [inbox, archive],
            sourceScope: sourceScope
        ))

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(plan.searchQuery == SearchQuery(
            folderID: "inbox",
            from: "invoices@example.com",
            execution: .cacheOnly
        ))
        #expect(plan.matchingMessageIDs == ["m-1"])
        #expect(plan.matchedFolderNames == ["Inbox"])
        #expect(presentation.detailRows.contains(
            MailboxActionAgentReviewDetailRow(
                title: "Criteria",
                value: "From invoices@example.com; Folder Inbox"
            )
        ))
    }

    @Test("folder refinement can use the focused folder")
    func folderRefinementCanUseTheFocusedFolder() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            request: "delete all mails from sender invoices@example.com only in this folder",
            headers: [
                Self.header(
                    id: "m-1",
                    from: "invoices@example.com",
                    subject: "Inbox invoice",
                    folderID: "inbox"
                ),
                Self.header(
                    id: "m-2",
                    from: "invoices@example.com",
                    subject: "Archive invoice",
                    folderID: "archive"
                )
            ],
            folders: [inbox, archive],
            focusedFolder: inbox,
            sourceScope: sourceScope
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(plan.searchQuery == SearchQuery(
            folderID: "inbox",
            from: "invoices@example.com",
            execution: .cacheOnly
        ))
        #expect(plan.matchingMessageIDs == ["m-1"])
        #expect(plan.matchedFolderNames == ["Inbox"])
        #expect(presentation.detailRows.contains(
            MailboxActionAgentReviewDetailRow(
                title: "Criteria",
                value: "From invoices@example.com; Folder Inbox"
            )
        ))
    }

    @Test("older-than refinement narrows search matches and review criteria")
    func olderThanRefinementNarrowsSearchMatchesAndReviewCriteria() throws {
        let cutoff = Self.daysAgo(30, from: fixedNow)
        let planner = MailboxActionAgentPlanner(
            idGenerator: { fixedPlanID },
            dateProvider: { fixedNow }
        )
        let result = planner.plan(
            request: "delete all mails from sender invoices@example.com older than 30 days",
            headers: [
                Self.header(
                    id: "m-old",
                    from: "invoices@example.com",
                    subject: "Old invoice",
                    date: Self.daysAgo(45, from: fixedNow)
                ),
                Self.header(
                    id: "m-new",
                    from: "invoices@example.com",
                    subject: "Recent invoice",
                    date: Self.daysAgo(5, from: fixedNow)
                )
            ],
            folders: [],
            focusedFolder: nil
        )
        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(plan.searchQuery == SearchQuery(
            from: "invoices@example.com",
            dateRange: Date.distantPast ... cutoff,
            execution: .cacheOnly
        ))
        #expect(plan.matchingMessageIDs == ["m-old"])
        #expect(presentation.detailRows.contains(
            MailboxActionAgentReviewDetailRow(
                title: "Criteria",
                value: "From invoices@example.com; Older than 30 days"
            )
        ))
    }

    @Test("move confirmation detail rows include the target folder")
    func moveConfirmationDetailRowsIncludeTheTargetFolder() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let plan = try #require(Self.planned(
            request: "move all mails from sender support@example.com to Receipts",
            headers: [
                Self.header(
                    id: "m-1",
                    from: "support@example.com",
                    subject: "Ticket",
                    folderID: "inbox"
                )
            ],
            folders: [inbox, receipts],
            sourceScope: sourceScope
        ))

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(presentation.detailRows.contains(
            MailboxActionAgentReviewDetailRow(title: "Action", value: "Move to Receipts")
        ))
    }

    @Test("move undo plan restores messages to their original folders")
    func moveUndoPlanRestoresMessagesToTheirOriginalFolders() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let plan = try #require(Self.planned(
            request: "move all mails from sender invoices@example.com to Receipts",
            headers: [
                Self.header(
                    id: "m-1",
                    from: "invoices@example.com",
                    subject: "Invoice 1",
                    folderID: "inbox"
                ),
                Self.header(
                    id: "m-2",
                    from: "invoices@example.com",
                    subject: "Invoice 2",
                    folderID: "archive"
                )
            ],
            folders: [inbox, archive, receipts]
        ))

        #expect(plan.undoPlan(folders: [inbox, archive, receipts]) == MailboxActionAgentUndoPlan(
            description: "Moved 2 messages to Receipts",
            steps: [
                .move(messageIDs: ["m-1"], to: inbox),
                .move(messageIDs: ["m-2"], to: archive)
            ]
        ))
    }

    @Test("archive undo plan restores messages to their original folders")
    func archiveUndoPlanRestoresMessagesToTheirOriginalFolders() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let plan = try #require(Self.planned(
            request: "archive all mails from sender alerts@example.com",
            headers: [
                Self.header(
                    id: "m-1",
                    from: "alerts@example.com",
                    subject: "Alert 1",
                    folderID: "inbox"
                ),
                Self.header(
                    id: "m-2",
                    from: "alerts@example.com",
                    subject: "Alert 2",
                    folderID: "receipts"
                )
            ],
            folders: [inbox, receipts, archive]
        ))

        #expect(plan.undoPlan(folders: [inbox, receipts, archive]) == MailboxActionAgentUndoPlan(
            description: "Archived 2 messages",
            steps: [
                .move(messageIDs: ["m-1"], to: inbox),
                .move(messageIDs: ["m-2"], to: receipts)
            ]
        ))
    }

    @Test("read-state undo plan restores original read groups")
    func readStateUndoPlanRestoresOriginalReadGroups() throws {
        let plan = try #require(Self.planned(
            request: "mark all mails from sender alerts@example.com as read",
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Unread", isRead: false),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Read", isRead: true),
                Self.header(id: "m-3", from: "alerts@example.com", subject: "Unread again", isRead: false)
            ]
        ))

        #expect(plan.undoPlan(folders: []) == MailboxActionAgentUndoPlan(
            description: "Marked 3 messages as Read",
            steps: [
                .setRead(false, messageIDs: ["m-1", "m-3"]),
                .setRead(true, messageIDs: ["m-2"])
            ]
        ))
    }

    @Test("flag undo plan restores original flag groups")
    func flagUndoPlanRestoresOriginalFlagGroups() throws {
        let plan = try #require(Self.planned(
            request: "unflag all mails from sender alerts@example.com",
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Flagged", isFlagged: true),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Plain", isFlagged: false),
                Self.header(id: "m-3", from: "alerts@example.com", subject: "Flagged again", isFlagged: true)
            ]
        ))

        #expect(plan.undoPlan(folders: []) == MailboxActionAgentUndoPlan(
            description: "Unflagged 3 messages",
            steps: [
                .setFlagged(true, messageIDs: ["m-1", "m-3"]),
                .setFlagged(false, messageIDs: ["m-2"])
            ]
        ))
    }

    @Test("delete undo plan is not offered")
    func deleteUndoPlanIsNotOffered() throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice")]
        ))

        #expect(plan.undoPlan(folders: []) == nil)
    }

    @Test("undo performer applies restore steps through a source-scoped backend")
    func undoPerformerAppliesRestoreStepsThroughSourceScopedBackend() async throws {
        let account = BrevAccount(
            id: "account-undo",
            displayName: "Undo",
            emailAddress: "undo@example.com",
            backendIdentifier: "mock",
            backendDisplayName: "Mock"
        )
        let mailbox = Mailbox(
            id: "primary",
            email: account.emailAddress,
            displayName: "Primary",
            isPrimary: true
        )
        let sourceID = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let backend = MockBackend(
            account: account,
            folders: [inbox, archive, receipts],
            messagesByFolder: [
                "receipts": [
                    Self.header(
                        id: "m-1",
                        from: "alerts@example.com",
                        subject: "Moved message",
                        folderID: "receipts",
                        isRead: true,
                        isFlagged: false
                    ),
                    Self.header(
                        id: "m-2",
                        from: "alerts@example.com",
                        subject: "Archived message",
                        folderID: "receipts",
                        isRead: true,
                        isFlagged: false
                    )
                ]
            ],
            mailboxes: [mailbox]
        )
        let undoPlan = MailboxActionAgentUndoPlan(
            description: "Mailbox Assistant undo",
            steps: [
                .move(messageIDs: ["m-1"], to: inbox),
                .move(messageIDs: ["m-2"], to: archive),
                .setRead(false, messageIDs: ["m-1"]),
                .setFlagged(true, messageIDs: ["m-2"])
            ]
        )

        try await MailboxActionAgentUndoPerformer.perform(
            undoPlan,
            backend: backend,
            sourceID: sourceID
        )

        let inboxHeaders = try await backend.messages(
            in: inbox,
            sourceID: sourceID,
            pageToken: nil
        ).headers
        let archiveHeaders = try await backend.messages(
            in: archive,
            sourceID: sourceID,
            pageToken: nil
        ).headers
        let restoredInboxMessage = try #require(inboxHeaders.first { $0.id == "m-1" })
        let restoredArchiveMessage = try #require(archiveHeaders.first { $0.id == "m-2" })

        #expect(restoredInboxMessage.folderID == "inbox")
        #expect(restoredInboxMessage.isRead == false)
        #expect(restoredArchiveMessage.folderID == "archive")
        #expect(restoredArchiveMessage.isFlagged)
    }

    @Test("undo performer surfaces backend restore failures")
    func undoPerformerSurfacesBackendRestoreFailures() async throws {
        let account = BrevAccount(
            id: "account-undo-failure",
            displayName: "Undo Failure",
            emailAddress: "undo-failure@example.com",
            backendIdentifier: "mock",
            backendDisplayName: "Mock"
        )
        let mailbox = Mailbox(
            id: "primary",
            email: account.emailAddress,
            displayName: "Primary",
            isPrimary: true
        )
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let backend = MockBackend(
            account: account,
            folders: [inbox],
            messagesByFolder: [
                "inbox": [
                    Self.header(
                        id: "m-1",
                        from: "alerts@example.com",
                        subject: "Moved message",
                        folderID: "inbox"
                    )
                ]
            ],
            mailboxes: [mailbox]
        )
        let undoPlan = MailboxActionAgentUndoPlan(
            description: "Mailbox Assistant undo",
            steps: [
                .move(messageIDs: ["m-1"], to: inbox)
            ]
        )
        let invalidSourceID = MailSourceID(accountID: account.id, mailboxID: "missing")

        await #expect(throws: MailBackendError.self) {
            try await MailboxActionAgentUndoPerformer.perform(
                undoPlan,
                backend: backend,
                sourceID: invalidSourceID
            )
        }
    }

    @Test("zero-match presentation does not expose a confirm action")
    func zeroMatchPresentationDoesNotExposeAConfirmAction() throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: []
        ))

        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(presentation.title == "No Matching Messages")
        #expect(presentation.message == "There are no messages from invoices@example.com to delete.")
        #expect(presentation.confirmButtonTitle == nil)
        #expect(presentation.cancelButtonTitle == "Close")
        #expect(presentation.requiredPhrase == nil)
        #expect(!presentation.canConfirm)
        #expect(presentation.sampleRows.isEmpty)
        #expect(presentation.detailRows.isEmpty)
        #expect(presentation.warningMessage == nil)
    }

    @Test("clarification presentation explains the missing input")
    func clarificationPresentationExplainsTheMissingInput() {
        #expect(
            MailboxActionAgentClarificationPresentation.message(for: .missingSender) ==
                "Tell me which sender to match."
        )
        #expect(
            MailboxActionAgentClarificationPresentation.message(for: .missingMoveTarget) ==
                "Tell me which folder to move the messages to."
        )
        #expect(
            MailboxActionAgentClarificationPresentation.message(for: .unknownFolder("Receipts")) ==
                "I couldn't find a folder named Receipts."
        )
        #expect(
            MailboxActionAgentClarificationPresentation.message(for: .ambiguousFolder("Receipts")) ==
                "More than one folder matches Receipts."
        )
        #expect(
            MailboxActionAgentClarificationPresentation.message(for: .unsupportedRequest) ==
                "I can only prepare sender-scoped delete, move, read-state, and flag actions right now."
        )
    }

    @Test("review input policy requires the exact confirmation phrase")
    func reviewInputPolicyRequiresTheExactConfirmationPhrase() throws {
        let plan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [
                Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
                Self.header(id: "m-2", from: "invoices@example.com", subject: "Invoice 2")
            ]
        ))
        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)

        #expect(MailboxActionAgentReviewInputPolicy.canConfirm(" DELETE 2 ", presentation: presentation))
        #expect(!MailboxActionAgentReviewInputPolicy.canConfirm("delete 2", presentation: presentation))
        #expect(!MailboxActionAgentReviewInputPolicy.canConfirm("DELETE 1", presentation: presentation))
    }

    @Test("completion presentation explains the applied action")
    func completionPresentationExplainsTheAppliedAction() throws {
        let deletePlan = try #require(Self.planned(
            request: "delete all mails from sender invoices@example.com",
            headers: [
                Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
                Self.header(id: "m-2", from: "invoices@example.com", subject: "Invoice 2")
            ]
        ))
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let movePlan = try #require(Self.planned(
            request: "move all mails from sender support@example.com to Receipts",
            headers: [Self.header(id: "m-3", from: "support@example.com", subject: "Ticket")],
            folders: [receipts]
        ))

        #expect(
            MailboxActionAgentCompletionPresentation.message(for: deletePlan) ==
                "Deleted 2 messages from invoices@example.com."
        )
        #expect(
            MailboxActionAgentCompletionPresentation.message(for: movePlan) ==
                "Moved 1 message from support@example.com to Receipts."
        )
        let markReadPlan = try #require(Self.planned(
            request: "mark all mails from sender alerts@example.com as read",
            headers: [Self.header(id: "m-4", from: "alerts@example.com", subject: "Alert", isRead: false)]
        ))
        let markUnreadPlan = try #require(Self.planned(
            request: "mark all mails from sender alerts@example.com as unread",
            headers: [Self.header(id: "m-5", from: "alerts@example.com", subject: "Alert", isRead: true)]
        ))
        #expect(
            MailboxActionAgentCompletionPresentation.message(for: markReadPlan) ==
                "Marked 1 message from alerts@example.com as read."
        )
        #expect(
            MailboxActionAgentCompletionPresentation.message(for: markUnreadPlan) ==
                "Marked 1 message from alerts@example.com as unread."
        )
        let flagPlan = try #require(Self.planned(
            request: "flag all mails from sender alerts@example.com",
            headers: [Self.header(id: "m-6", from: "alerts@example.com", subject: "Alert", isFlagged: false)]
        ))
        let unflagPlan = try #require(Self.planned(
            request: "unflag all mails from sender alerts@example.com",
            headers: [Self.header(id: "m-7", from: "alerts@example.com", subject: "Alert", isFlagged: true)]
        ))
        #expect(
            MailboxActionAgentCompletionPresentation.message(for: flagPlan) ==
                "Flagged 1 message from alerts@example.com."
        )
        #expect(
            MailboxActionAgentCompletionPresentation.message(for: unflagPlan) ==
                "Unflagged 1 message from alerts@example.com."
        )
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let archivePlan = try #require(Self.planned(
            request: "archive all mails from sender alerts@example.com",
            headers: [Self.header(id: "m-8", from: "alerts@example.com", subject: "Alert")],
            folders: [archive]
        ))
        #expect(
            MailboxActionAgentCompletionPresentation.message(for: archivePlan) ==
                "Archived 1 message from alerts@example.com."
        )
    }

    @Test("structured delete intent decodes and plans through deterministic planner")
    func structuredDeleteIntentDecodesAndPlansThroughDeterministicPlanner() throws {
        let intent = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
        {
          "action": "delete",
          "senderEmail": "INVOICES@example.com"
        }
        """))
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            intent: intent,
            headers: [
                Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
                Self.header(id: "m-2", from: "alerts@example.com", subject: "Alert"),
                Self.header(id: "m-3", from: "INVOICES@example.com", subject: "Invoice 2")
            ],
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(intent.senderEmail == "invoices@example.com")
        #expect(plan.request == "delete all mails from sender invoices@example.com")
        #expect(plan.operation == .delete)
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.searchQuery == SearchQuery(from: "invoices@example.com", execution: .cacheOnly))
    }

    @Test("structured move intent can target the focused folder")
    func structuredMoveIntentCanTargetTheFocusedFolder() throws {
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let intent = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
        {
          "action": "move",
          "senderEmail": "support@example.com",
          "useFocusedFolder": true
        }
        """))
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            intent: intent,
            headers: [Self.header(id: "m-1", from: "support@example.com", subject: "Ticket")],
            folders: [receipts],
            focusedFolder: receipts
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.request == "move all mails from sender support@example.com to this folder here")
        #expect(plan.operation == .move(to: receipts))
        #expect(plan.matchingMessageIDs == ["m-1"])
    }

    @Test("structured delete intent can carry folder and age refinements")
    func structuredDeleteIntentCanCarryFolderAndAgeRefinements() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let cutoff = Self.daysAgo(30, from: fixedNow)
        let intent = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
        {
          "action": "delete",
          "senderEmail": "INVOICES@example.com",
          "sourceFolderName": "Inbox",
          "olderThanDays": 30
        }
        """))
        let planner = MailboxActionAgentPlanner(
            idGenerator: { fixedPlanID },
            dateProvider: { fixedNow }
        )

        let result = planner.plan(
            intent: intent,
            headers: [
                Self.header(
                    id: "m-old",
                    from: "invoices@example.com",
                    subject: "Old invoice",
                    folderID: "inbox",
                    date: Self.daysAgo(45, from: fixedNow)
                ),
                Self.header(
                    id: "m-new",
                    from: "invoices@example.com",
                    subject: "Recent invoice",
                    folderID: "inbox",
                    date: Self.daysAgo(5, from: fixedNow)
                )
            ],
            folders: [inbox],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(intent.requestText == "delete all mails from sender invoices@example.com only in Inbox older than 30 days")
        #expect(plan.searchQuery == SearchQuery(
            folderID: "inbox",
            from: "invoices@example.com",
            dateRange: Date.distantPast ... cutoff,
            execution: .cacheOnly
        ))
        #expect(plan.matchingMessageIDs == ["m-old"])
    }

    @Test("structured mark-read intent decodes and plans through deterministic planner")
    func structuredMarkReadIntentDecodesAndPlansThroughDeterministicPlanner() throws {
        let intent = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
        {
          "action": "markRead",
          "senderEmail": "ALERTS@example.com"
        }
        """))
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            intent: intent,
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isRead: false),
                Self.header(id: "m-2", from: "friend@example.com", subject: "Hello", isRead: false),
                Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2", isRead: false)
            ],
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(intent.requestText == "mark all mails from sender alerts@example.com as read")
        #expect(plan.confirmationChallenge.requiredPhrase == "MARK READ 2")
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
    }

    @Test("structured flag intent decodes and plans through deterministic planner")
    func structuredFlagIntentDecodesAndPlansThroughDeterministicPlanner() throws {
        let intent = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
        {
          "action": "flag",
          "senderEmail": "ALERTS@example.com"
        }
        """))
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            intent: intent,
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1", isFlagged: false),
                Self.header(id: "m-2", from: "friend@example.com", subject: "Hello", isFlagged: false),
                Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2", isFlagged: false)
            ],
            folders: [],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(intent.requestText == "flag all mails from sender alerts@example.com")
        #expect(plan.confirmationChallenge.requiredPhrase == "FLAG 2")
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
    }

    @Test("structured archive intent decodes and plans through deterministic planner")
    func structuredArchiveIntentDecodesAndPlansThroughDeterministicPlanner() throws {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let intent = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
        {
          "action": "archive",
          "senderEmail": "ALERTS@example.com"
        }
        """))
        let planner = MailboxActionAgentPlanner(idGenerator: { fixedPlanID })

        let result = planner.plan(
            intent: intent,
            headers: [
                Self.header(id: "m-1", from: "alerts@example.com", subject: "Alert 1"),
                Self.header(id: "m-2", from: "friend@example.com", subject: "Hello"),
                Self.header(id: "m-3", from: "ALERTS@example.com", subject: "Alert 2")
            ],
            folders: [archive],
            focusedFolder: nil
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(intent.requestText == "archive all mails from sender alerts@example.com")
        #expect(plan.confirmationChallenge.requiredPhrase == "ARCHIVE 2")
        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
    }

    @Test("structured intent rejects unsupported fields before planning")
    func structuredIntentRejectsUnsupportedFieldsBeforePlanning() {
        #expect(throws: MailboxActionAgentStructuredIntentError.unsupportedFields(["messageIDs"])) {
            _ = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
            {
              "action": "delete",
              "senderEmail": "invoices@example.com",
              "messageIDs": ["m-1", "m-2"]
            }
            """))
        }
        #expect(throws: MailboxActionAgentStructuredIntentError.unsupportedFields(["folderID", "messageIDs"])) {
            _ = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
            {
              "action": "delete",
              "senderEmail": "invoices@example.com",
              "folderID": "inbox",
              "messageIDs": ["m-1"]
            }
            """))
        }
    }

    @Test("structured intent rejects invalid operations and missing move targets")
    func structuredIntentRejectsInvalidOperationsAndMissingMoveTargets() {
        #expect(throws: MailboxActionAgentStructuredIntentError.unsupportedAction("snooze")) {
            _ = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
            {
              "action": "snooze",
              "senderEmail": "invoices@example.com"
            }
            """))
        }
        #expect(throws: MailboxActionAgentStructuredIntentError.missingMoveTarget) {
            _ = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
            {
              "action": "move",
              "senderEmail": "support@example.com"
            }
            """))
        }
    }

    @Test("structured intent rejects invalid age refinements")
    func structuredIntentRejectsInvalidAgeRefinements() {
        #expect(throws: MailboxActionAgentStructuredIntentError.invalidField("olderThanDays")) {
            _ = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
            {
              "action": "delete",
              "senderEmail": "invoices@example.com",
              "olderThanDays": 0
            }
            """))
        }
        #expect(throws: MailboxActionAgentStructuredIntentError.invalidField("olderThanDays")) {
            _ = try MailboxActionAgentStructuredIntentDecoder.decode(Self.jsonData("""
            {
              "action": "delete",
              "senderEmail": "invoices@example.com",
              "olderThanDays": "30"
            }
            """))
        }
    }

    @Test("resolver searches cache-only by sender before building delete plan")
    func resolverSearchesCacheOnlyBySenderBeforeBuildingDeletePlan() async throws {
        let search = RecordingMailboxActionSearch(results: [
            Self.header(id: "m-1", from: "invoices@example.com", subject: "Invoice 1"),
            Self.header(id: "m-2", from: "invoices@example.com.au", subject: "Wrong sender"),
            Self.header(id: "m-3", from: "INVOICES@example.com", subject: "Invoice 2")
        ])
        let resolver = MailboxActionAgentRequestResolver(idGenerator: { fixedPlanID })

        let result = try await resolver.resolve(
            request: "delete all mails from sender invoices@example.com",
            folders: [],
            focusedFolder: nil,
            sourceID: sourceID,
            search: { query, sourceID in
                await search.search(query: query, sourceID: sourceID)
            }
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.matchingMessageIDs == ["m-1", "m-3"])
        #expect(plan.confirmationChallenge.requiredPhrase == "DELETE 2")
        #expect(await search.queries == [
            SearchQuery(from: "invoices@example.com", execution: .cacheOnly)
        ])
        #expect(await search.sourceIDs == [sourceID])
    }

    @Test("resolver searches cache-only before building focused-folder move plan")
    func resolverSearchesCacheOnlyBeforeBuildingFocusedFolderMovePlan() async throws {
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)
        let search = RecordingMailboxActionSearch(results: [
            Self.header(id: "m-1", from: "support@example.com", subject: "Ticket")
        ])
        let resolver = MailboxActionAgentRequestResolver(idGenerator: { fixedPlanID })

        let result = try await resolver.resolve(
            request: "move all mails from sender support@example.com to this folder here",
            folders: [receipts],
            focusedFolder: receipts,
            sourceID: sourceID,
            search: { query, sourceID in
                await search.search(query: query, sourceID: sourceID)
            }
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.operation == .move(to: receipts))
        #expect(plan.matchingMessageIDs == ["m-1"])
        #expect(await search.queries == [
            SearchQuery(from: "support@example.com", execution: .cacheOnly)
        ])
    }

    @Test("resolver searches cache-only using folder and age refinements")
    func resolverSearchesCacheOnlyUsingFolderAndAgeRefinements() async throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let cutoff = Self.daysAgo(30, from: fixedNow)
        let search = RecordingMailboxActionSearch(results: [
            Self.header(
                id: "m-old",
                from: "invoices@example.com",
                subject: "Old invoice",
                folderID: "inbox",
                date: Self.daysAgo(45, from: fixedNow)
            ),
            Self.header(
                id: "m-new",
                from: "invoices@example.com",
                subject: "Recent invoice",
                folderID: "inbox",
                date: Self.daysAgo(5, from: fixedNow)
            )
        ])
        let resolver = MailboxActionAgentRequestResolver(
            idGenerator: { fixedPlanID },
            dateProvider: { fixedNow }
        )

        let result = try await resolver.resolve(
            request: "delete all mails from sender invoices@example.com only in Inbox older than 30 days",
            folders: [inbox],
            focusedFolder: nil,
            sourceID: sourceID,
            search: { query, sourceID in
                await search.search(query: query, sourceID: sourceID)
            }
        )

        guard case .planned(let plan) = result else {
            Issue.record("Expected a plan, got \(result)")
            return
        }

        #expect(plan.matchingMessageIDs == ["m-old"])
        #expect(await search.queries == [
            SearchQuery(
                folderID: "inbox",
                from: "invoices@example.com",
                dateRange: Date.distantPast ... cutoff,
                execution: .cacheOnly
            )
        ])
    }

    @Test("resolver returns clarification without searching")
    func resolverReturnsClarificationWithoutSearching() async throws {
        let search = RecordingMailboxActionSearch(results: [
            Self.header(id: "m-1", from: "support@example.com", subject: "Ticket")
        ])
        let resolver = MailboxActionAgentRequestResolver(idGenerator: { fixedPlanID })

        let result = try await resolver.resolve(
            request: "delete all newsletters",
            folders: [],
            focusedFolder: nil,
            sourceID: sourceID,
            search: { query, sourceID in
                await search.search(query: query, sourceID: sourceID)
            }
        )

        #expect(result == .clarificationRequired(.missingSender))
        #expect(await search.queries.isEmpty)
        #expect(await search.sourceIDs.isEmpty)
    }

    private static func header(
        id: String,
        from: String,
        subject: String,
        folderID: String = "inbox",
        date: Date = Date(timeIntervalSince1970: 1_779_960_600),
        isRead: Bool = false,
        isFlagged: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: Correspondent(name: nil, email: from),
            subject: subject,
            snippet: "snippet",
            date: date,
            isRead: isRead,
            isFlagged: isFlagged
        )
    }

    private static func planned(
        request: String,
        headers: [MessageHeader],
        folders: [Folder] = [],
        sourceScope: MailboxActionAgentSourceScope = .currentMailbox,
        dateProvider: @escaping @Sendable () -> Date = {
            Date(timeIntervalSince1970: 1_779_964_800)
        }
    ) -> MailboxActionAgentPlan? {
        let planner = MailboxActionAgentPlanner(idGenerator: {
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        }, dateProvider: dateProvider)
        let result = planner.plan(
            request: request,
            headers: headers,
            folders: folders,
            focusedFolder: nil,
            sourceScope: sourceScope
        )
        guard case .planned(let plan) = result else { return nil }
        return plan
    }

    private static func daysAgo(_ days: Int, from date: Date) -> Date {
        date.addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
    }

    private static func jsonData(_ string: String) -> Data {
        Data(string.utf8)
    }
}

private actor RecordingMutationQueue: OfflineMutationQueue {
    private var items: [PendingMutation] = []

    func enqueue(_ mutation: PendingMutation) async throws {
        items.append(mutation)
    }

    func pending() async throws -> [PendingMutation] {
        items
    }

    func update(_ mutation: PendingMutation) async throws {
        guard let index = items.firstIndex(where: { $0.id == mutation.id }) else { return }
        items[index] = mutation
    }

    func remove(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }

    func removeAll() async throws {
        items.removeAll()
    }
}

private actor RecordingMailboxActionSearch {
    private let results: [MessageHeader]
    private(set) var queries: [SearchQuery] = []
    private(set) var sourceIDs: [MailSourceID?] = []

    init(results: [MessageHeader]) {
        self.results = results
    }

    func search(query: SearchQuery, sourceID: MailSourceID?) -> [MessageHeader] {
        queries.append(query)
        sourceIDs.append(sourceID)
        return results
    }
}
