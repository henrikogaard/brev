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

@Suite("Compose AI generative actions")
struct ComposeAIGenerativeActionTests {
    @Test("prompt draft packages only the explicit prompt")
    func promptDraftPackagesOnlyExplicitPrompt() throws {
        let context = try #require(ComposeAIGenerativeContext.promptDraft(prompt: " Write a launch note. "))

        #expect(context.messages == [
            AIMessage(role: .user, content: "Write a launch note.")
        ])
        #expect(context.instruction == "Draft a new email from the user's prompt.")
    }

    @Test("reply draft packages minimal reply context")
    func replyDraftPackagesMinimalReplyContext() throws {
        let header = MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            to: [Correspondent(name: "Henrik", email: "henrik@example.org")],
            cc: [Correspondent(name: "Maja", email: "maja@example.org")],
            bcc: [Correspondent(name: "Hidden", email: "hidden@example.org")],
            subject: "Launch checklist",
            snippet: "Can you review the checklist today?",
            date: Date(timeIntervalSince1970: 0)
        )

        let context = try #require(ComposeAIGenerativeContext.replyDraft(
            replyingTo: header,
            draftBody: "I can review it after lunch."
        ))

        #expect(context.messages.count == 2)
        #expect(context.messages[0].role == .user)
        #expect(context.messages[0].content.contains("From: Alex <alex@example.org>"))
        #expect(context.messages[0].content.contains("Subject: Launch checklist"))
        #expect(context.messages[0].content.contains("Snippet: Can you review the checklist today?"))
        #expect(!context.messages[0].content.contains("hidden@example.org"))
        #expect(context.messages[1] == AIMessage(
            role: .user,
            content: "Current draft: I can review it after lunch."
        ))
        #expect(context.instruction == "Draft an email reply from the provided compose context.")
    }

    @Test("subject suggestion packages current draft without unrelated mailbox context")
    func subjectSuggestionPackagesCurrentDraftOnly() throws {
        let context = try #require(ComposeAIGenerativeContext.subjectSuggestion(
            bodyText: "Here is the launch checklist for review.",
            currentSubject: "Old subject"
        ))

        #expect(context.messages == [
            AIMessage(
                role: .user,
                content: "Current subject: Old subject\nDraft body: Here is the launch checklist for review."
            )
        ])
        #expect(context.instruction == "Suggest one concise email subject line. Return only the subject text.")
    }

    @Test("subject preview applies only while draft and subject snapshots match")
    func subjectPreviewAppliesOnlyWhileSnapshotsMatch() {
        let request = ComposeAIShortcutRequest(
            action: .improveWriting,
            bodyText: "Here is the launch checklist.",
            target: .wholeDraft
        )
        let preview = ComposeAIPreviewState(
            id: 7,
            action: .suggestSubject,
            request: request,
            providerLabel: AIWriterDisclosure.defaultProvider.transparencyLabel,
            phase: .loading,
            applyTarget: .subject(subjectSnapshot: "Old subject"),
            originalText: "Here is the launch checklist."
        ).succeeded(with: "Launch checklist review\n")

        #expect(preview.replaceActionTitle == "Replace Subject")
        #expect(ComposeAIPreviewApplyPolicy.appliedSubject(
            preview,
            currentBodyText: "Here is the launch checklist.",
            currentSubject: "Old subject"
        ) == "Launch checklist review")
        #expect(ComposeAIPreviewApplyPolicy.appliedSubject(
            preview,
            currentBodyText: "Here is the launch checklist. Edited.",
            currentSubject: "Old subject"
        ) == nil)
        #expect(ComposeAIPreviewApplyPolicy.appliedSubject(
            preview,
            currentBodyText: "Here is the launch checklist.",
            currentSubject: "New subject"
        ) == nil)
    }

    @Test("required generative action context is explicit")
    func requiredGenerativeActionContextIsExplicit() {
        #expect(ComposeAIGenerativeContext.promptDraft(prompt: " \n\t ") == nil)
        #expect(ComposeAIGenerativeContext.subjectSuggestion(bodyText: " ", currentSubject: "") == nil)
        #expect(ComposeAIGenerativeContext.replyDraft(replyingTo: nil, draftBody: "") == nil)
    }
}
