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

@testable import BrevMail
import Foundation
import Testing

@Suite("Compose dismissal policy")
struct ComposeDismissalPolicyTests {
    private let blank = ComposeDismissalContent.blank

    private func content(
        to: [String] = [],
        subject: String = "",
        body: String = "",
        attachments: Int = 0
    ) -> ComposeDismissalContent {
        ComposeDismissalContent(
            to: to,
            cc: [],
            bcc: [],
            subject: subject,
            userBody: body,
            attachmentCount: attachments
        )
    }

    private func state(
        isDirty: Bool = false,
        isBusy: Bool = false,
        isUndoSendPending: Bool = false,
        hasCompletedExplicitOperation: Bool = false
    ) -> ComposeDismissalState {
        ComposeDismissalState(
            isDirty: isDirty,
            isBusy: isBusy,
            isUndoSendPending: isUndoSendPending,
            hasCompletedExplicitOperation: hasCompletedExplicitOperation
        )
    }

    // MARK: Dirty detection

    @Test("an untouched compose is not dirty")
    func untouchedComposeIsClean() {
        #expect(!ComposeDismissalPolicy.isDirty(current: blank, baseline: blank))
    }

    @Test("typing a subject, recipient, body or attaching a file makes the draft dirty")
    func editsMakeDraftDirty() {
        #expect(ComposeDismissalPolicy.isDirty(current: content(subject: "Hi"), baseline: blank))
        #expect(ComposeDismissalPolicy.isDirty(current: content(to: ["a@b.co"]), baseline: blank))
        #expect(ComposeDismissalPolicy.isDirty(current: content(body: "Hello"), baseline: blank))
        #expect(ComposeDismissalPolicy.isDirty(current: content(attachments: 1), baseline: blank))
    }

    @Test("whitespace-only input does not count as an edit")
    func whitespaceOnlyIsNotAnEdit() {
        #expect(!ComposeDismissalPolicy.isDirty(current: content(subject: "  ", body: "\n\n"), baseline: blank))
    }

    @Test("a reply whose prefilled fields are unchanged is clean")
    func unchangedReplyIsClean() {
        let reply = content(to: ["ingrid@acme.example"], subject: "Re: Notes")
        #expect(!ComposeDismissalPolicy.isDirty(current: reply, baseline: reply))
    }

    @Test("editing a prefilled reply makes it dirty")
    func editedReplyIsDirty() {
        let baseline = content(to: ["ingrid@acme.example"], subject: "Re: Notes")
        let edited = content(to: ["ingrid@acme.example"], subject: "Re: Notes", body: "Thanks")
        #expect(ComposeDismissalPolicy.isDirty(current: edited, baseline: baseline))
    }

    @Test("removing everything from a saved draft is an edit")
    func clearingSavedDraftIsDirty() {
        let baseline = content(to: ["a@b.co"], subject: "Plan", body: "Text")
        #expect(ComposeDismissalPolicy.isDirty(current: blank, baseline: baseline))
    }

    // MARK: Cancel decision

    @Test("cancel on a clean draft closes without asking")
    func cancelOnCleanDraftCloses() {
        #expect(ComposeDismissalPolicy.decision(for: state(isDirty: false)) == .closeNow)
    }

    @Test("cancel on a dirty draft asks Delete Draft or Save Draft")
    func cancelOnDirtyDraftAsks() {
        #expect(ComposeDismissalPolicy.decision(for: state(isDirty: true)) == .askDeleteOrSave)
    }

    @Test("a finished send, save or discard closes without asking even when dirty")
    func completedOperationClosesWithoutAsking() {
        let finished = state(isDirty: true, hasCompletedExplicitOperation: true)
        #expect(ComposeDismissalPolicy.decision(for: finished) == .closeNow)
    }

    @Test("cancel is ignored while sending, saving or counting down to send")
    func cancelIgnoredWhileBusy() {
        #expect(ComposeDismissalPolicy.decision(for: state(isDirty: true, isBusy: true)) == .ignore)
        #expect(ComposeDismissalPolicy.decision(for: state(isDirty: false, isUndoSendPending: true)) == .ignore)
    }

    // MARK: Interactive (swipe-down) dismissal

    @Test("swipe-down is allowed only on a clean draft")
    func swipeDownAllowedOnlyWhenClean() {
        #expect(!ComposeDismissalPolicy.blocksInteractiveDismissal(for: state(isDirty: false)))
        #expect(ComposeDismissalPolicy.blocksInteractiveDismissal(for: state(isDirty: true)))
    }

    @Test("swipe-down is blocked while sending or counting down to send")
    func swipeDownBlockedWhileBusy() {
        #expect(ComposeDismissalPolicy.blocksInteractiveDismissal(for: state(isBusy: true)))
        #expect(ComposeDismissalPolicy.blocksInteractiveDismissal(for: state(isUndoSendPending: true)))
    }

    @Test("swipe-down is allowed once the operation that dirtied the draft has finished")
    func swipeDownAllowedAfterCompletion() {
        let finished = state(isDirty: true, hasCompletedExplicitOperation: true)
        #expect(!ComposeDismissalPolicy.blocksInteractiveDismissal(for: finished))
    }

    @Test("a blocked swipe routes to the same choice as Cancel")
    func blockedSwipeRoutesToCancelChoice() {
        let dirty = state(isDirty: true)
        #expect(ComposeDismissalPolicy.decision(forAttemptedSwipeWith: dirty) == ComposeDismissalPolicy.decision(for: dirty))
        #expect(ComposeDismissalPolicy.decision(forAttemptedSwipeWith: dirty) == .askDeleteOrSave)
    }

    // MARK: User-authored body

    @Test("the quoted original and managed signature do not count as user text")
    func userBodyExcludesQuoteAndSignature() {
        let marker = "On Jan 1, Ada wrote:"
        let body = "\n\n-- \nHenrik\n\n\(marker)\n> original"
        let stripped = ComposeDismissalContent.userBody(
            from: body,
            quoteProtection: ComposeQuoteProtection(marker: marker, edge: .bottom),
            managedSignatureBody: "Henrik"
        )
        #expect(stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("text typed above the quote counts as user text")
    func userBodyKeepsTypedText() {
        let marker = "On Jan 1, Ada wrote:"
        let body = "Thanks!\n\n\(marker)\n> original"
        let stripped = ComposeDismissalContent.userBody(
            from: body,
            quoteProtection: ComposeQuoteProtection(marker: marker, edge: .bottom),
            managedSignatureBody: nil
        )
        #expect(stripped.trimmingCharacters(in: .whitespacesAndNewlines) == "Thanks!")
    }

    @Test("a top-quote reply keeps text typed below the quote")
    func userBodyTopQuote() {
        let marker = "On Jan 1, Ada wrote:"
        let body = "\(marker)\n> original\n\nSounds good"
        let stripped = ComposeDismissalContent.userBody(
            from: body,
            quoteProtection: ComposeQuoteProtection(marker: marker, edge: .top),
            managedSignatureBody: nil
        )
        #expect(stripped.trimmingCharacters(in: .whitespacesAndNewlines) == "Sounds good")
    }

    @Test("without quote protection the body is used as written")
    func userBodyWithoutQuote() {
        let stripped = ComposeDismissalContent.userBody(
            from: "Hello",
            quoteProtection: nil,
            managedSignatureBody: nil
        )
        #expect(stripped == "Hello")
    }
}
