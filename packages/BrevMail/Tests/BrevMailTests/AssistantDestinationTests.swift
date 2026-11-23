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

import BrevAI
import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("Assistant sidebar destination and answer cards")
@MainActor
struct AssistantDestinationTests {
    private static let source = MailSourceID(accountID: "acct-1", mailboxID: "box-1")
    private static let now = Date(timeIntervalSince1970: 1_794_500_000)

    private struct MockAssistantAI: AIBackend {
        let identifier = "mock-local"
        let displayName = "On this Mac"
        let transparencyLabel = "On this Mac"
        let replyText: String
        let onInvoke: @Sendable () -> Void

        func generateReply(to messages: [AIMessage], instruction: String?) async throws -> AIResponse {
            onInvoke()
            return AIResponse(text: replyText)
        }

        func shortcut(_ action: AIShortcutAction, on text: String) async throws -> AIResponse {
            onInvoke()
            return AIResponse(text: replyText)
        }
    }

    private actor InvocationCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private static func citation(
        id: String,
        senderName: String? = "Daniel Reyes",
        senderEmail: String = "daniel@example.com",
        subject: String = "Launch plan",
        snippet: String = "Can you check section 2?",
        hoursAgo: Double = 1,
        isRead: Bool = false,
        isFlagged: Bool = false,
        isAnswered: Bool = false
    ) -> MailboxChatCitation {
        MailboxChatCitation(
            id: id,
            folderID: "inbox",
            sourceID: source,
            subject: subject,
            date: now.addingTimeInterval(-hoursAgo * 3600),
            senderName: senderName,
            senderEmail: senderEmail,
            snippet: snippet,
            isRead: isRead,
            isFlagged: isFlagged,
            isAnswered: isAnswered
        )
    }

    @Test("Answer cards group real citations into Needs you, Worth a look, and Updates & newsletters with tags and chips")
    func buildsGroupedAnswerCardsFromRealCitations() {
        let urgent = Self.citation(
            id: "m1",
            senderName: "Daniel Reyes",
            senderEmail: "daniel@example.com",
            subject: "Contract sign-off",
            hoursAgo: 1,
            isRead: false,
            isFlagged: true
        )
        let unreadHuman = Self.citation(
            id: "m2",
            senderName: "Maya Okafor",
            senderEmail: "maya@example.com",
            subject: "Design review",
            hoursAgo: 3,
            isRead: false
        )
        let worthLook = Self.citation(
            id: "m3",
            senderName: "Priya",
            senderEmail: "priya@example.com",
            subject: "Notes from Monday",
            hoursAgo: 8,
            isRead: true,
            isAnswered: true
        )
        let update = Self.citation(
            id: "m4",
            senderName: "Linear",
            senderEmail: "notifications@linear.app",
            subject: "Weekly digest",
            hoursAgo: 12,
            isRead: false
        )

        let presentation = AssistantAnswerCardsBuilder.build(
            citations: [urgent, unreadHuman, worthLook, update],
            locale: Locale(identifier: "en_US")
        )

        #expect(presentation.sections.count == 3)
        #expect(presentation.sections[0].kind == .needsYou)
        #expect(presentation.sections[0].cards.map(\.messageID) == ["m1", "m2"])
        #expect(presentation.sections[0].cards[0].tags.contains(.urgent))
        #expect(presentation.sections[0].cards[0].tags.contains(.reply))

        #expect(presentation.sections[1].kind == .worthALook)
        #expect(presentation.sections[1].cards.map(\.messageID) == ["m3"])
        #expect(presentation.sections[1].cards[0].tags.contains(.read))

        #expect(presentation.sections[2].kind == .updatesAndNewsletters)
        #expect(presentation.sections[2].cards.map(\.messageID) == ["m4"])

        #expect(presentation.summaryChips.contains("2 need you"))
        #expect(presentation.summaryChips.contains("1 worth a look"))

        #expect(presentation.actionChips.contains { chip in
            if case .reply(let name, let card) = chip {
                return name == "Daniel Reyes" && card.messageID == "m1"
            }
            return false
        })
        #expect(presentation.actionChips.contains { chip in
            if case .archiveUpdates(let count, let cards) = chip {
                return count == 1 && cards.map(\.messageID) == ["m4"]
            }
            return false
        })
    }

    @Test("MailboxChatController with mock AI only runs on explicit send and produces real grounded cards")
    func controllerWithMockAIRunsOnlyOnSend() async {
        let counter = InvocationCounter()
        let ai = MockAssistantAI(replyText: "Daniel needs your sign-off today.") {
            Task { await counter.increment() }
        }
        let realHeader = MessageHeader(
            id: "real-42",
            threadID: "t-42",
            folderID: "inbox",
            from: Correspondent(name: "Daniel Reyes", email: "daniel@example.com"),
            subject: "Contract sign-off",
            snippet: "Please confirm before 5pm.",
            date: Self.now,
            isRead: false,
            isFlagged: true
        )

        let controller = MailboxChatController(
            scope: .account,
            sourceID: Self.source,
            aiBackend: ai,
            search: { query, _ in
                #expect(query.execution == .cacheOnly)
                return [realHeader]
            }
        )

        #expect(await counter.count == 0)

        await controller.send(userText: "What needs me today?")
        #expect(controller.turns.count == 2)
        guard case .answer(let text, let citations, let providerLabel) = controller.turns[1] else {
            Issue.record("Expected answer turn")
            return
        }
        #expect(text == "Daniel needs your sign-off today.")
        #expect(providerLabel == "On this Mac")
        #expect(citations.count == 1)
        #expect(citations[0].id == "real-42")
        #expect(citations[0].senderEmail == "daniel@example.com")
        #expect(citations[0].isFlagged == true)

        let cards = AssistantAnswerCardsBuilder.build(citations: citations, locale: Locale(identifier: "en_US"))
        #expect(cards.sections.first?.cards.first?.messageID == "real-42")
        #expect(cards.sections.first?.cards.first?.folderID == "inbox")
        #expect(cards.sections.first?.cards.first?.sourceID == Self.source)
    }

    @Test("Navigation preserves concrete mailbox source when opening Assistant and clears cleanly")
    func navigationAssistantDestination() {
        let navigation = MailNavigationState()
        navigation.selectFolder("inbox", in: Self.source)
        #expect(!navigation.isAssistantSelected)
        navigation.selectAssistantDestination()
        #expect(navigation.isAssistantSelected)
        #expect(navigation.assistantSourceID == Self.source)
        navigation.selectFolder("inbox", in: Self.source)
        #expect(!navigation.isAssistantSelected)
    }

    @Test("Assistant prompt submission gate blocks disabled, unconsented, and missing-backend prompts")
    func availabilityGateBlocksDisabledOrUnconsented() {
        let disabled = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: false, consentGiven: false),
            hasProviderBackend: true
        )
        #expect(
            AssistantPromptSubmissionGate.evaluate(
                prompt: "What needs me today?",
                isSending: false,
                disabledReason: MailboxChatAvailability.disabledReason(in: disabled)
            ) == .requestConsent
        )

        let unconsented = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: false),
            hasProviderBackend: true
        )
        #expect(
            AssistantPromptSubmissionGate.evaluate(
                prompt: "What needs me today?",
                isSending: false,
                disabledReason: MailboxChatAvailability.disabledReason(in: unconsented)
            ) == .requestConsent
        )

        let missingBackend = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            hasProviderBackend: false
        )
        #expect(
            AssistantPromptSubmissionGate.evaluate(
                prompt: "What needs me today?",
                isSending: false,
                disabledReason: MailboxChatAvailability.disabledReason(in: missingBackend)
            ) == .openSettings
        )

        let ready = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            hasProviderBackend: true
        )
        #expect(
            AssistantPromptSubmissionGate.evaluate(
                prompt: "  What needs me today?  ",
                isSending: false,
                disabledReason: MailboxChatAvailability.disabledReason(in: ready)
            ) == .send("What needs me today?")
        )
    }

    @Test("Archive all stages deterministic multi-sender review, rejects non-Archive All Mail, and supports Undo")
    func archiveAllStagesDeterministicReviewedPlan() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let archive = try #require(folders.first { $0.role == .archive })
        let inboxHeaders = try await backend.messages(in: inbox, pageToken: nil).headers
        let m1 = try #require(inboxHeaders.first)
        let m2 = try #require(inboxHeaders.dropFirst().first)
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)

        let card1 = AssistantConversationCard(
            messageID: m1.id,
            folderID: inbox.id,
            sourceID: sourceID,
            senderName: m1.from.name ?? m1.from.email,
            senderEmail: m1.from.email,
            subject: m1.subject,
            snippet: m1.snippet,
            date: m1.date,
            section: .updatesAndNewsletters,
            tags: [],
            citation: MailboxChatCitation(
                id: m1.id,
                folderID: inbox.id,
                sourceID: sourceID,
                subject: m1.subject,
                date: m1.date,
                senderName: m1.from.name,
                senderEmail: m1.from.email,
                snippet: m1.snippet,
                isRead: m1.isRead,
                isFlagged: m1.isFlagged,
                isAnswered: m1.isAnswered
            )
        )
        let card2 = AssistantConversationCard(
            messageID: m2.id,
            folderID: inbox.id,
            sourceID: sourceID,
            senderName: m2.from.name ?? m2.from.email,
            senderEmail: m2.from.email,
            subject: m2.subject,
            snippet: m2.snippet,
            date: m2.date,
            section: .updatesAndNewsletters,
            tags: [],
            citation: MailboxChatCitation(
                id: m2.id,
                folderID: inbox.id,
                sourceID: sourceID,
                subject: m2.subject,
                date: m2.date,
                senderName: m2.from.name,
                senderEmail: m2.from.email,
                snippet: m2.snippet,
                isRead: m2.isRead,
                isFlagged: m2.isFlagged,
                isAnswered: m2.isAnswered
            )
        )

        let undoQueue = UndoQueue(timeout: 30)
        let controller = MailboxChatController(
            scope: .account,
            sourceID: sourceID,
            aiBackend: nil,
            actionFolders: folders,
            executeAction: { plan in
                guard case .archive(let targetFolder) = plan.operation else { return "unexpected" }
                try await MailboxActionArchiveExecutor.archive(
                    plan: plan,
                    to: targetFolder,
                    sourceID: sourceID,
                    folders: folders,
                    backend: backend,
                    undoQueue: undoQueue
                )
                return MailboxActionAgentCompletionPresentation.message(for: plan)
            },
            search: { _, _ in [] }
        )

        controller.stageArchiveCards([card1, card2])
        guard case .actionReview(let plan, _)? = controller.turns.last else {
            Issue.record("Expected action review turn")
            return
        }
        #expect(plan.matchingMessageIDs == [m1.id, m2.id])
        #expect(plan.operation == .archive(to: archive))
        // Both distinct senders must be surfaced in the review challenge.
        #expect(plan.confirmationChallenge.prompt.contains(m1.from.email.lowercased()))
        #expect(plan.confirmationChallenge.prompt.contains(m2.from.email.lowercased()))
        #expect(plan.sampleMessages.count == 2)

        // Wrong phrase does not execute
        await controller.confirmAction(planID: plan.id, phrase: "wrong")
        #expect(!undoQueue.canUndo)

        // Exact phrase executes strictly the displayed card IDs and registers Undo
        await controller.confirmAction(planID: plan.id, phrase: plan.confirmationChallenge.requiredPhrase)
        #expect(undoQueue.canUndo)
        let afterArchive = try await backend.messages(in: inbox, pageToken: nil).headers.map(\.id)
        #expect(!afterArchive.contains(m1.id))
        #expect(!afterArchive.contains(m2.id))

        // Undo restores both messages to Inbox
        let undone = await undoQueue.undo()?.value ?? false
        #expect(undone)
        let afterUndo = try await backend.messages(in: inbox, pageToken: nil).headers.map(\.id)
        #expect(afterUndo.contains(m1.id))
        #expect(afterUndo.contains(m2.id))

        // An ordinary IMAP folder classified as `.allMail` must NOT be treated as an Archive target.
        let imapAllOnlyFolders = [
            Folder(id: "INBOX", name: "Inbox", role: .inbox),
            Folder(id: "All", name: "All", role: .allMail),
        ]
        let noArchiveController = MailboxChatController(
            scope: .account,
            sourceID: sourceID,
            aiBackend: nil,
            actionFolders: imapAllOnlyFolders,
            executeAction: { _ in "never" },
            search: { _, _ in [] }
        )
        noArchiveController.stageArchiveCards([card1])
        if case .clarification? = noArchiveController.turns.last {
            // Expected clarification
        } else {
            Issue.record("Expected clarification when no dedicated Archive folder exists")
        }

        // Genuine Gmail API (supportsAllMailArchive: true) and Gmail IMAP ([Gmail]/All Mail) succeed.
        let gmailAPIFolders = [
            Folder(id: "INBOX", name: "Inbox", role: .inbox),
            Folder(id: "ALL_MAIL", name: "All Mail", role: .allMail),
        ]
        let gmailAPIPlan = MailboxActionAgentPlanner().planArchive(
            cards: [card1],
            folders: gmailAPIFolders,
            supportsAllMailArchive: true
        )
        if case .planned(let p) = gmailAPIPlan {
            #expect(p.operation == .archive(to: gmailAPIFolders[1]))
        } else {
            Issue.record("Expected Gmail API All Mail archive plan")
        }

        let gmailIMAPFolders = [
            Folder(id: "INBOX", name: "Inbox", role: .inbox),
            Folder(id: "[Gmail]/All Mail", name: "All Mail", role: .allMail),
        ]
        let gmailIMAPPlan = MailboxActionAgentPlanner().planArchive(
            cards: [card1],
            folders: gmailIMAPFolders,
            supportsAllMailArchive: false
        )
        if case .planned(let p) = gmailIMAPPlan {
            #expect(p.operation == .archive(to: gmailIMAPFolders[1]))
        } else {
            Issue.record("Expected Gmail IMAP All Mail archive plan")
        }
    }

    @Test("Multi-folder archive executor suppresses partial nil-receipt Undo and preserves Undo on later folder failure")
    func multiFolderArchiveExecutorUndoSemantics() async throws {
        final class PartialUndoBackend: MailBackend, @unchecked Sendable {
            let account = BrevAccount(id: "acct", displayName: "Test", emailAddress: "t@example.org")
            let capabilities: BackendCapabilities = []
            var nilReceiptFolders: Set<String> = []
            var failingFolders: Set<String> = []
            var restoredIDs: [String] = []
            func connect() async throws {}
            func disconnect() async {}
            func folders() async throws -> [Folder] { [] }
            func refresh(folder: Folder) async throws {}
            func currentMailbox() async throws -> Mailbox {
                Mailbox(id: "acct", email: "t@example.org", displayName: "Test", isPrimary: true)
            }

            func switchMailbox(id: String) async throws {}
            func messages(in folder: Folder,
                          pageToken: String?) async throws -> (headers: [MessageHeader], nextPageToken: String?) { (
                [],
                nil
            ) }
            func body(for messageID: String) async throws -> MessageBody { MessageBody(messageID: messageID) }
            func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {}
            func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {}
            func move(messageIDs: [String], to folder: Folder) async throws {}
            func moveWithUndo(
                messageIDs: [String],
                from sourceFolder: Folder,
                to destinationFolder: Folder,
                sourceID: MailSourceID
            ) async throws -> MailMoveUndo? {
                if failingFolders.contains(sourceFolder.id) {
                    throw MailBackendError.backendSpecific(message: "Read-only folder")
                }
                if nilReceiptFolders.contains(sourceFolder.id) {
                    return nil
                }
                return MailMoveUndo(
                    sourceID: sourceID,
                    originalFolder: sourceFolder
                ) { [weak self] in
                    self?.restoredIDs.append(contentsOf: messageIDs)
                    return [:]
                }
            }

            func delete(messageIDs: [String]) async throws {}
            func save(draft: Draft) async throws -> Draft { draft }
            func discard(draftID: String) async throws {}
            func send(draft: Draft) async throws -> SendResult { SendResult() }
            func search(_ query: SearchQuery) async throws -> [MessageHeader] { [] }
            func calendarEvent(from attachmentID: String) async throws -> CalendarEvent { throw MailBackendError.notSupported([])
            }

            func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {}
            func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }
            func sourceID(for mailbox: Mailbox) -> MailSourceID { MailSourceID(accountID: account.id, mailboxID: mailbox.id) }
            func extensionService<Service>(_ type: Service.Type) -> Service? { nil }
        }

        let sourceID = MailSourceID(accountID: "acct", mailboxID: "acct")
        let folders = [
            Folder(id: "INBOX", name: "Inbox", role: .inbox),
            Folder(id: "PROJECTS", name: "Projects", role: .custom),
            Folder(id: "ARCHIVE", name: "Archive", role: .archive),
        ]
        let now = Date()
        let cards = [
            AssistantConversationCard(
                messageID: "m1",
                folderID: "INBOX",
                sourceID: sourceID,
                senderName: "A",
                senderEmail: "a@example.org",
                subject: "One",
                snippet: "",
                date: now,
                section: .updatesAndNewsletters,
                tags: [],
                citation: MailboxChatCitation(
                    id: "m1", folderID: "INBOX", sourceID: sourceID, subject: "One", date: now,
                    senderName: "A", senderEmail: "a@example.org", snippet: "", isRead: false, isFlagged: false, isAnswered: false
                )
            ),
            AssistantConversationCard(
                messageID: "m2",
                folderID: "PROJECTS",
                sourceID: sourceID,
                senderName: "B",
                senderEmail: "b@example.org",
                subject: "Two",
                snippet: "",
                date: now,
                section: .updatesAndNewsletters,
                tags: [],
                citation: MailboxChatCitation(
                    id: "m2", folderID: "PROJECTS", sourceID: sourceID, subject: "Two", date: now,
                    senderName: "B", senderEmail: "b@example.org", snippet: "", isRead: false, isFlagged: false, isAnswered: false
                )
            ),
        ]
        guard case .planned(let plan) = MailboxActionAgentPlanner().planArchive(cards: cards, folders: folders) else {
            Issue.record("Expected plan")
            return
        }

        // Case A: one folder returns nil receipt -> whole-command Undo suppressed.
        let nilBackend = PartialUndoBackend()
        nilBackend.nilReceiptFolders = ["INBOX"]
        let queueA = UndoQueue(timeout: 30)
        try await MailboxActionArchiveExecutor.archive(
            plan: plan, to: folders[2], sourceID: sourceID, folders: folders, backend: nilBackend, undoQueue: queueA
        )
        #expect(!queueA.canUndo)

        // Case B: second folder throws after first succeeds -> Undo still restores first folder.
        let failBackend = PartialUndoBackend()
        failBackend.failingFolders = ["PROJECTS"]
        let queueB = UndoQueue(timeout: 30)
        do {
            try await MailboxActionArchiveExecutor.archive(
                plan: plan, to: folders[2], sourceID: sourceID, folders: folders, backend: failBackend, undoQueue: queueB
            )
            Issue.record("Expected PROJECTS folder error")
        } catch {
            // Expected failure
        }
        #expect(queueB.canUndo)
        _ = await queueB.undo()?.value
        #expect(failBackend.restoredIDs == ["m1"])
    }

    @Test("Assistant destination strings have Norwegian localizations")
    func norwegianCopy() throws {
        let catalog = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let requiredKeys = [
            "Ask anything about your mail…",
            "What needs me today?",
            "Who hasn't replied?",
            "Who hasn't replied to me?",
            "Needs you",
            "Worth a look",
            "Updates & newsletters",
            "Urgent",
            "Read",
            "%lld need you",
            "%lld worth a look",
            "Reply to %@…",
            "Archive all %lld",
        ]
        for key in requiredKeys {
            let entry = try #require(catalog[key] as? [String: Any], "Missing catalog key \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let nb = try #require(localizations["nb"] as? [String: Any])
            let unitValue = (nb["stringUnit"] as? [String: Any])?["value"] as? String
            let hasVariations = (nb["variations"] as? [String: Any]) != nil
            #expect((unitValue?.isEmpty == false) || hasVariations, "Missing nb localization for \(key)")
        }
    }
}
