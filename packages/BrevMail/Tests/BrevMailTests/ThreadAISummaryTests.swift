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
