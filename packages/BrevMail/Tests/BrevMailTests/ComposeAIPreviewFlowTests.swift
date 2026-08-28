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
@testable import BrevMail
import Foundation
import Testing

@Suite("Compose AI preview flow")
struct ComposeAIPreviewFlowTests {
    @Test("successful whole-draft result previews before replace")
    func successfulWholeDraftResultPreviewsBeforeReplace() {
        let request = ComposeAIShortcutRequest(
            action: .formal,
            bodyText: "Ship it today.",
            target: .wholeDraft
        )
        let preview = ComposeAIPreviewState(
            id: 1,
            action: .shortcut(.formal, scope: .wholeDraft),
            request: request,
            providerLabel: AIWriterDisclosure.defaultProvider.transparencyLabel,
            phase: .loading
        ).succeeded(with: "Please ship it today.")

        #expect(preview.title == AIShortcutAction.formal.displayLabel)
        #expect(preview.originalText == "Ship it today.")
        #expect(preview.generatedText == "Please ship it today.")
        #expect(preview.replaceActionTitle == "Replace Draft")
        #expect(preview.copyText == "Please ship it today.")
        #expect(ComposeAIPreviewApplyPolicy.appliedText(
            preview,
            action: .replaceTarget,
            currentBodyText: "Ship it today.",
            currentSelection: nil,
            insertionPoint: nil
        ) == "Please ship it today.")
    }

    @Test("selected-text result applies only to unchanged selection")
    func selectedTextResultAppliesOnlyToUnchangedSelection() throws {
        let body = "Please ship Brev today."
        let selection = try #require(ComposeBodyTextSelection(
            bodyText: body,
            nsRange: (body as NSString).range(of: "ship Brev")
        ))
        let request = ComposeAIShortcutRequest(
            action: .formal,
            bodyText: body,
            target: .selection(selection)
        )
        let preview = ComposeAIPreviewState(
            id: 2,
            action: .shortcut(.formal, scope: .selection),
            request: request,
            providerLabel: AIWriterDisclosure.defaultProvider.transparencyLabel,
            phase: .loading
        ).succeeded(with: "send Brev")

        #expect(preview.replaceActionTitle == "Replace Selection")
        #expect(ComposeAIPreviewApplyPolicy.appliedText(
            preview,
            action: .replaceTarget,
            currentBodyText: body,
            currentSelection: selection,
            insertionPoint: nil
        ) == "Please send Brev today.")
        #expect(ComposeAIPreviewApplyPolicy.appliedText(
            preview,
            action: .replaceTarget,
            currentBodyText: "Please ship Brev tomorrow.",
            currentSelection: selection,
            insertionPoint: nil
        ) == nil)
    }

    @Test("insert at cursor requires unchanged draft and insertion point")
    func insertAtCursorRequiresUnchangedDraftAndInsertionPoint() throws {
        let body = "Hello "
        let insertionPoint = try #require(ComposeBodyInsertionPoint(
            bodyText: body,
            nsRange: NSRange(location: (body as NSString).length, length: 0)
        ))
        let request = ComposeAIShortcutRequest(
            action: .expand,
            bodyText: body,
            target: .wholeDraft
        )
        let preview = ComposeAIPreviewState(
            id: 3,
            action: .shortcut(.expand, scope: .wholeDraft),
            request: request,
            providerLabel: AIWriterDisclosure.defaultProvider.transparencyLabel,
            phase: .loading
        ).succeeded(with: "from Brev")

        #expect(ComposeAIPreviewApplyPolicy.appliedText(
            preview,
            action: .insertAtCursor,
            currentBodyText: body,
            currentSelection: nil,
            insertionPoint: insertionPoint
        ) == "Hello from Brev")
        #expect(ComposeAIPreviewApplyPolicy.appliedText(
            preview,
            action: .insertAtCursor,
            currentBodyText: "Hello edited ",
            currentSelection: nil,
            insertionPoint: insertionPoint
        ) == nil)
    }

    @Test("loading and failed previews cannot apply but can retry when snapshot matches")
    func loadingAndFailedPreviewsCannotApplyButCanRetryWhenSnapshotMatches() {
        let request = ComposeAIShortcutRequest(
            action: .shorten,
            bodyText: "Please shorten this.",
            target: .wholeDraft
        )
        let loading = ComposeAIPreviewState(
            id: 4,
            action: .shortcut(.shorten, scope: .wholeDraft),
            request: request,
            providerLabel: AIWriterDisclosure.defaultProvider.transparencyLabel,
            phase: .loading
        )
        let failed = loading.failed(with: "AI Writer failed.")

        #expect(loading.generatedText == nil)
        #expect(ComposeAIPreviewApplyPolicy.appliedText(
            loading,
            action: .replaceTarget,
            currentBodyText: "Please shorten this.",
            currentSelection: nil,
            insertionPoint: nil
        ) == nil)
        #expect(failed.errorMessage == "AI Writer failed.")
        #expect(failed.canRetry(currentBodyText: "Please shorten this.", currentSelection: nil))
        #expect(!failed.canRetry(currentBodyText: "Edited text.", currentSelection: nil))
    }
}
