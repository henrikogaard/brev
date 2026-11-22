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

    @Test("AI availability gate blocks disabled or unconsented Assistant requests")
    func availabilityGateBlocksDisabledOrUnconsented() {
        let disabled = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: false, consentGiven: false),
            hasProviderBackend: true
        )
        #expect(MailboxChatAvailability.disabledReason(in: disabled) == .notEnabled)

        let unconsented = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: false),
            hasProviderBackend: true
        )
        #expect(MailboxChatAvailability.disabledReason(in: unconsented) == .consentRequired)

        let ready = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            hasProviderBackend: true
        )
        #expect(MailboxChatAvailability.disabledReason(in: ready) == nil)
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
