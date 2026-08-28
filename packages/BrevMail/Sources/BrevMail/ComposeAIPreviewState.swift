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
import Foundation

struct ComposeAIPreviewState: Equatable, Identifiable, Sendable {
    enum Phase: Equatable, Sendable {
        case loading
        case success(String)
        case failure(String)
    }

    let id: Int
    let action: ComposeAIAction
    let request: ComposeAIShortcutRequest
    let providerLabel: String
    let operation: ComposeAIPreviewOperation
    let applyTarget: ComposeAIPreviewApplyTarget
    let originalTextOverride: String?
    var phase: Phase

    init(
        id: Int,
        action: ComposeAIAction,
        request: ComposeAIShortcutRequest,
        providerLabel: String,
        phase: Phase,
        operation: ComposeAIPreviewOperation? = nil,
        applyTarget: ComposeAIPreviewApplyTarget = .body,
        originalText: String? = nil
    ) {
        self.id = id
        self.action = action
        self.request = request
        self.providerLabel = providerLabel
        self.phase = phase
        self.operation = operation ?? .shortcut(request.action)
        self.applyTarget = applyTarget
        originalTextOverride = originalText
    }

    var title: String {
        action.title
    }

    var originalText: String {
        originalTextOverride ?? request.inputText
    }

    var generatedText: String? {
        guard case .success(let text) = phase else {
            return nil
        }
        return text
    }

    var errorMessage: String? {
        guard case .failure(let message) = phase else {
            return nil
        }
        return message
    }

    var copyText: String? {
        generatedText
    }

    var replaceActionTitle: String {
        if case .subject = applyTarget {
            return "Replace Subject"
        }
        switch request.target {
        case .wholeDraft:
            return "Replace Draft"
        case .selection:
            return "Replace Selection"
        }
    }

    func succeeded(with text: String) -> Self {
        var updated = self
        updated.phase = .success(text)
        return updated
    }

    func failed(with message: String) -> Self {
        var updated = self
        updated.phase = .failure(message)
        return updated
    }

    func canRetry(
        currentBodyText: String,
        currentSelection: ComposeBodyTextSelection?,
        currentSubject: String? = nil
    ) -> Bool {
        guard ComposeAIShortcutResponsePolicy.canApplySnapshot(
            request: request,
            currentBodyText: currentBodyText,
            currentSelection: currentSelection
        ) else {
            return false
        }
        if case .subject(let subjectSnapshot) = applyTarget {
            return currentSubject == subjectSnapshot
        }
        return true
    }
}

enum ComposeAIPreviewOperation: Equatable, Sendable {
    case shortcut(AIShortcutAction)
    case generateReply(messages: [AIMessage], instruction: String?)
}

enum ComposeAIPreviewApplyTarget: Equatable, Sendable {
    case body
    case subject(subjectSnapshot: String)
}

enum ComposeAIPreviewApplyAction: Equatable, Sendable {
    case replaceTarget
    case insertAtCursor
}

enum ComposeAIPreviewApplyPolicy {
    static func appliedText(
        _ preview: ComposeAIPreviewState,
        action: ComposeAIPreviewApplyAction,
        currentBodyText: String,
        currentSelection: ComposeBodyTextSelection?,
        insertionPoint: ComposeBodyInsertionPoint?
    ) -> String? {
        guard let generatedText = preview.generatedText else {
            return nil
        }
        guard preview.applyTarget == .body else {
            return nil
        }
        guard ComposeAIShortcutResponsePolicy.canApplySnapshot(
            request: preview.request,
            currentBodyText: currentBodyText,
            currentSelection: currentSelection
        ) else {
            return nil
        }

        switch action {
        case .replaceTarget:
            return ComposeAIShortcutResponsePolicy.appliedPreviewText(
                for: preview.request,
                currentBodyText: currentBodyText,
                currentSelection: currentSelection,
                responseText: generatedText
            )
        case .insertAtCursor:
            return insertionPoint?.insertingText(generatedText, in: currentBodyText)
        }
    }

    static func appliedSubject(
        _ preview: ComposeAIPreviewState,
        currentBodyText: String,
        currentSubject: String
    ) -> String? {
        guard case .subject(let subjectSnapshot) = preview.applyTarget else {
            return nil
        }
        guard currentSubject == subjectSnapshot else {
            return nil
        }
        guard ComposeAIShortcutResponsePolicy.canApplySnapshot(
            request: preview.request,
            currentBodyText: currentBodyText,
            currentSelection: nil
        ) else {
            return nil
        }
        guard let generatedText = preview.generatedText else {
            return nil
        }
        let subject = generatedText
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return subject.isEmpty ? nil : subject
    }
}
