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

@Suite("Thread AI summary")
struct ThreadAISummaryTests {
    @Test("availability requires enabled consented AI backend and loaded messages")
    func availabilityRequiresEnabledConsentedAIBackendAndLoadedMessages() {
        let base = ThreadAISummaryAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            hasProviderBackend: true,
            isBusy: false,
            hasActiveRequest: false,
            messageCount: 2
        )

        #expect(ThreadAISummaryAvailability.disabledReason(in: base) == nil)
        #expect(ThreadAISummaryAvailability.disabledReason(in: base.with(hasProviderBackend: false)) == .missingBackend)
        #expect(ThreadAISummaryAvailability.disabledReason(in: base.with(settings: .defaults)) == .notEnabled)
        #expect(ThreadAISummaryAvailability.disabledReason(
            in: base.with(settings: AIWriterSettings(isEnabled: true, consentGiven: false))
        ) == .consentRequired)
        #expect(ThreadAISummaryAvailability.disabledReason(in: base.with(isBusy: true)) == .busy)
        #expect(ThreadAISummaryAvailability.disabledReason(in: base.with(hasActiveRequest: true)) == .requestInFlight)
        #expect(ThreadAISummaryAvailability.disabledReason(in: base.with(messageCount: 0)) == .messageRequired)
    }

    @Test("context builder packages bounded thread content without message identifiers")
    func contextBuilderPackagesBoundedThreadContentWithoutMessageIdentifiers() throws {
        let headers = (1 ... 4).map { index in
            header(
                id: "message-\(index)",
                sender: "sender\(index)@example.com",
                subject: "Planning thread",
                snippet: "Snippet \(index)",
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let bodies = Dictionary(uniqueKeysWithValues: headers.map {
            ($0.id, MessageBody(
                messageID: $0.id,
                plainText: "Body for \($0.id) with project details.",
                attachments: [Attachment(
                    id: "attachment-\($0.id)",
                    name: "secret.pdf",
                    mimeType: "application/pdf",
                    sizeBytes: 12
                )]
            ))
        })

        let context = try #require(ThreadAISummaryContextBuilder.context(
            headers: headers,
            bodies: bodies,
            maxMessages: 2,
            maxCharacters: 1000
        ))

        #expect(context.includedMessageCount == 2)
        #expect(context.totalMessageCount == 4)
        #expect(context.wasTruncated)
        #expect(context.messages.count == 1)
        #expect(context.messages[0].role == .user)
        #expect(context.messages[0].content.contains("2 older messages omitted"))
        #expect(context.messages[0].content.contains("sender3@example.com"))
        #expect(context.messages[0].content.contains("Body for message-4"))
        #expect(!context.messages[0].content.contains("messageID"))
        #expect(!context.messages[0].content.contains("folderID"))
        #expect(!context.messages[0].content.contains("threadID"))
        #expect(!context.messages[0].content.contains("attachment-message-4"))
        #expect(!context.messages[0].content.contains("secret.pdf"))
        #expect(context.instruction.contains("Summary"))
        #expect(context.instruction.contains("Next actions"))
    }

    @Test("summary presentation separates bullets from next actions")
    func summaryPresentationSeparatesBulletsFromNextActions() {
        let presentation = ThreadAISummaryPresentation.make(
            responseText: """
            Summary:
            - Alex asked for the launch checklist.
            - Henrik will review by Friday.

            Next actions:
            - Henrik: review checklist.
            - Alex: send final copy.
            """,
            providerLabel: AIWriterDisclosure.defaultProvider.transparencyLabel,
            wasTruncated: true
        )

        #expect(presentation.summaryBullets == [
            "Alex asked for the launch checklist.",
            "Henrik will review by Friday."
        ])
        #expect(presentation.nextActions == [
            "Henrik: review checklist.",
            "Alex: send final copy."
        ])
        #expect(presentation.providerLabel == AIWriterDisclosure.defaultProvider.transparencyLabel)
        #expect(presentation.contextNote == "Summarized a bounded thread window.")
    }

    @Test("on-device context budget bounds thread summary window below standard cloud cap")
    func onDeviceContextBudgetBoundsSummaryWindow() throws {
        let headers = (1 ... 10).map { index in
            header(
                id: "msg-\(index)",
                sender: "sender\(index)@example.com",
                subject: "Quarterly roadmap",
                snippet: "Snippet \(index)",
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let bodies = Dictionary(uniqueKeysWithValues: headers.map {
            ($0.id, MessageBody(messageID: $0.id, plainText: String(repeating: "Detail ", count: 400)))
        })
        let budget = AIBackendContextBudget.onDevice
        let included = ThreadAISummaryContextBuilder.includedHeaders(from: headers, maxMessages: budget.maxSourceMessages)
        #expect(included.count == budget.maxSourceMessages)
        #expect(included.last?.id == "msg-10")

        let context = try #require(ThreadAISummaryContextBuilder.context(
            headers: headers,
            bodies: bodies,
            maxMessages: budget.maxSourceMessages,
            maxCharacters: budget.maxTotalContextBytes,
            maxUTF8Bytes: budget.maxTotalContextBytes
        ))
        #expect(context.includedMessageCount == budget.maxSourceMessages)
        #expect(context.wasTruncated)
        #expect(context.messages[0].content.count <= budget.maxTotalContextBytes)
        #expect(AISafetyPolicy.serializeUntrustedMailContent(context.messages[0].content).utf8.count <= budget
            .maxTotalContextBytes)
    }

    @Test("multibyte threads under the character cap still report truncation when wrapped UTF-8 exceeds budget")
    func multibyteSummaryReportsByteTruncation() throws {
        let headers = [
            header(
                id: "msg-jp",
                sender: "sender@example.com",
                subject: "会議の議事録",
                snippet: "要点",
                date: Date(timeIntervalSince1970: 100)
            )
        ]
        // 4,000 Japanese characters fit well under an 8,000-character limit,
        // but require ~12,000 UTF-8 bytes and exceed the 8,000-byte on-device cap.
        let bodies = [
            "msg-jp": MessageBody(messageID: "msg-jp", plainText: String(repeating: "会議", count: 2000))
        ]
        let budget = AIBackendContextBudget.onDevice
        let context = try #require(ThreadAISummaryContextBuilder.context(
            headers: headers,
            bodies: bodies,
            maxMessages: budget.maxSourceMessages,
            maxCharacters: budget.maxTotalContextBytes,
            maxUTF8Bytes: budget.maxTotalContextBytes
        ))
        #expect(context.wasTruncated)
        #expect(AISafetyPolicy.serializeUntrustedMailContent(context.messages[0].content).utf8.count <= budget
            .maxTotalContextBytes)
    }

    @Test("switching conversations clears manual summary state and active request")
    func switchingConversationsResetsManualSummaryState() {
        let source = MailSourceID(accountID: "acct-1", mailboxID: "acct-1")
        let threadA = [header(id: "m-a", sender: "a@example.com", subject: "A", snippet: "Hi", date: Date())]
        let threadB = [MessageHeader(
            id: "m-b",
            threadID: "thread-b",
            folderID: "inbox",
            from: Correspondent(name: "B", email: "b@example.com"),
            subject: "B",
            snippet: "Hello",
            date: Date(),
            isRead: true
        )]
        let idA = ThreadAISummarySessionState.conversationIdentity(
            sourceID: source,
            accountID: "acct-1",
            headers: threadA
        )
        let idB = ThreadAISummarySessionState.conversationIdentity(
            sourceID: source,
            accountID: "acct-1",
            headers: threadB
        )
        #expect(idA != idB)

        var session = ThreadAISummarySessionState(
            conversationIdentity: idA,
            activeRequest: ThreadAISummaryRequest(threadID: "thread-1", messageIDs: ["m-a"]),
            state: .success(ThreadAISummaryPresentation.make(
                responseText: "Summary:\n- Old conversation summary.",
                providerLabel: "On this Mac",
                wasTruncated: false
            ))
        )

        #expect(session.switchConversation(to: idA) == false)
        #expect(session.state != nil)

        #expect(session.switchConversation(to: idB) == true)
        #expect(session.conversationIdentity == idB)
        #expect(session.activeRequest == nil)
        #expect(session.state == nil)
    }

    private func header(
        id: String,
        sender: String,
        subject: String,
        snippet: String,
        date: Date
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: nil, email: sender),
            subject: subject,
            snippet: snippet,
            date: date
        )
    }
}

private extension ThreadAISummaryAvailabilityState {
    func with(
        settings: AIWriterSettings? = nil,
        hasProviderBackend: Bool? = nil,
        isBusy: Bool? = nil,
        hasActiveRequest: Bool? = nil,
        messageCount: Int? = nil
    ) -> ThreadAISummaryAvailabilityState {
        ThreadAISummaryAvailabilityState(
            settings: settings ?? self.settings,
            hasProviderBackend: hasProviderBackend ?? self.hasProviderBackend,
            isBusy: isBusy ?? self.isBusy,
            hasActiveRequest: hasActiveRequest ?? self.hasActiveRequest,
            messageCount: messageCount ?? self.messageCount
        )
    }
}
