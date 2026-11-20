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

/// Quick reply starters in the docked reply (#302 slice 2).
@Suite("Inline reply starters")
struct InlineReplyStarterTests {
    private let header = MessageHeader(
        id: "m1", threadID: "t1", folderID: "inbox",
        from: Correspondent(name: "Maya", email: "maya@example.com"),
        subject: "Tuesday?", snippet: "Can we meet Tuesday?",
        date: Date(timeIntervalSince1970: 0)
    )

    @Test("the presets come in the issue's order")
    func presetOrder() {
        #expect(InlineReplyStarter.presets == [.reply, .sayYes, .declinePolitely, .askForMoreTime, .askAQuestion])
    }

    @Test("a starter adds its intent after the reply context")
    func starterAddsIntent() throws {
        let context = try #require(ComposeAIGenerativeContext.replyDraft(
            replyingTo: header, draftBody: "", guidance: InlineReplyStarter.declinePolitely.guidance
        ))
        #expect(context.messages.count == 2)
        #expect(context.messages[0].content.contains("Subject: Tuesday?"))
        #expect(context.messages[1] == AIMessage(role: .user, content: "Reply intent: Decline politely."))
        #expect(context.instruction == "Draft an email reply from the provided compose context.")
    }

    @Test("plain Reply and a blank description add no intent")
    func noIntent() throws {
        #expect(InlineReplyStarter.reply.guidance == nil)
        #expect(InlineReplyStarter.described("   ").guidance == nil)
        let context = try #require(ComposeAIGenerativeContext.replyDraft(
            replyingTo: header, draftBody: "", guidance: InlineReplyStarter.reply.guidance
        ))
        #expect(context.messages.count == 1)
    }

    @Test("a description becomes the intent, trimmed")
    func describedIntent() {
        #expect(InlineReplyStarter.described("  yes, but next week ").guidance == "yes, but next week")
    }

    @Test("a starter is a reply-context AI action")
    func starterAction() {
        let action = ComposeAIAction.replyStarter(.sayYes)
        #expect(action.scope == .replyContext)
        #expect(action.requirements == [.replyContext])
        #expect(action.id == "replyStarter.sayYes")
        #expect(ComposeAIAction.replyStarter(.described("x")).id == "replyStarter.described")
    }

    @Test("starters show only in the docked reply with AI Writer ready", arguments: [
        (true, true, true, true, true, true),
        (false, true, true, true, true, false),
        (true, false, true, true, true, false),
        (true, true, false, true, true, false),
        (true, true, true, false, true, false),
        (true, true, true, true, false, false),
    ])
    func visibility(
        isInline: Bool, enabled: Bool, consent: Bool, supported: Bool, hasBackend: Bool, expected: Bool
    ) {
        let availability = ComposeAIAvailabilityState(
            settings: AIWriterSettings(isEnabled: enabled, consentGiven: consent),
            hasProviderBackend: hasBackend,
            backendSupportsAIWriter: supported,
            isBusy: false,
            hasActiveRequest: false
        )
        #expect(InlineReplyStarter.isVisible(
            isInline: isInline, hasReplyContext: true, availability: availability
        ) == expected)
        #expect(!InlineReplyStarter.isVisible(
            isInline: isInline, hasReplyContext: false, availability: availability
        ))
    }
}
