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

struct ComposeAIShortcutRequest: Equatable, Sendable {
    let action: AIShortcutAction
    let inputText: String
    let bodyTextSnapshot: String
    let target: ComposeAIShortcutTarget

    init(action: AIShortcutAction, inputText: String) {
        self.action = action
        self.inputText = inputText
        bodyTextSnapshot = inputText
        target = .wholeDraft
    }

    init(
        action: AIShortcutAction,
        bodyText: String,
        target: ComposeAIShortcutTarget
    ) {
        self.action = action
        bodyTextSnapshot = bodyText
        self.target = target
        switch target {
        case .wholeDraft:
            inputText = bodyText
        case .selection(let selection):
            inputText = selection.selectedText
        }
    }
}

enum ComposeAIShortcutTarget: Equatable, Sendable {
    case wholeDraft
    case selection(ComposeBodyTextSelection)
}

enum ComposeAIShortcutResponsePolicy {
    static func canApplyResponse(
        request: ComposeAIShortcutRequest,
        activeRequest: ComposeAIShortcutRequest?,
        currentBodyText: String
    ) -> Bool {
        canApplyResponse(
            request: request,
            activeRequest: activeRequest,
            currentBodyText: currentBodyText,
            currentSelection: nil
        )
    }

    static func canApplyResponse(
        request: ComposeAIShortcutRequest,
        activeRequest: ComposeAIShortcutRequest?,
        currentBodyText: String,
        currentSelection: ComposeBodyTextSelection?
    ) -> Bool {
        guard activeRequest == request else {
            return false
        }
        return canApplySnapshot(
            request: request,
            currentBodyText: currentBodyText,
            currentSelection: currentSelection
        )
    }

    static func canApplySnapshot(
        request: ComposeAIShortcutRequest,
        currentBodyText: String,
        currentSelection: ComposeBodyTextSelection?
    ) -> Bool {
        guard currentBodyText == request.bodyTextSnapshot else {
            return false
        }
        switch request.target {
        case .wholeDraft:
            return true
        case .selection(let selection):
            return currentSelection == selection
        }
    }

    static func appliedText(
        for request: ComposeAIShortcutRequest,
        activeRequest: ComposeAIShortcutRequest?,
        currentBodyText: String,
        currentSelection: ComposeBodyTextSelection?,
        responseText: String
    ) -> String? {
        guard canApplyResponse(
            request: request,
            activeRequest: activeRequest,
            currentBodyText: currentBodyText,
            currentSelection: currentSelection
        ) else {
            return nil
        }
        switch request.target {
        case .wholeDraft:
            return responseText
        case .selection(let selection):
            return selection.replacingSelection(in: currentBodyText, with: responseText)
        }
    }

    static func appliedPreviewText(
        for request: ComposeAIShortcutRequest,
        currentBodyText: String,
        currentSelection: ComposeBodyTextSelection?,
        responseText: String
    ) -> String? {
        guard canApplySnapshot(
            request: request,
            currentBodyText: currentBodyText,
            currentSelection: currentSelection
        ) else {
            return nil
        }
        switch request.target {
        case .wholeDraft:
            return responseText
        case .selection(let selection):
            return selection.replacingSelection(in: currentBodyText, with: responseText)
        }
    }
}
