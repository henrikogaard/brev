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

enum ComposeAIAction: Equatable, Identifiable, Sendable {
    case draftFromPrompt
    case shortcut(AIShortcutAction, scope: ComposeAIActionScope)
    case draftReply
    case suggestSubject

    static let shortcutOrder: [AIShortcutAction] = [
        .improveWriting,
        .shorten,
        .expand,
        .formal,
        .casual,
        .friendly,
        .fixSpelling,
        .translate
    ]

    static let toolbarActions: [ComposeAIAction] =
        [.draftFromPrompt]
            + shortcutOrder.map { .shortcut($0, scope: .wholeDraft) }
            + [.suggestSubject]

    static let wholeDraftShortcutActions: [ComposeAIAction] =
        shortcutOrder.map { .shortcut($0, scope: .wholeDraft) }

    static let selectedTextActions: [ComposeAIAction] =
        shortcutOrder.map { .shortcut($0, scope: .selection) }

    var id: String {
        switch self {
        case .draftFromPrompt:
            return "draftFromPrompt"
        case .shortcut(let action, let scope):
            return "shortcut.\(action.rawValue).\(scope.rawValue)"
        case .draftReply:
            return "draftReply"
        case .suggestSubject:
            return "suggestSubject"
        }
    }

    var title: String {
        switch self {
        case .draftFromPrompt:
            return "Draft from Prompt"
        case .shortcut(let action, _):
            return action.displayLabel
        case .draftReply:
            return "Draft Reply"
        case .suggestSubject:
            return "Suggest Subject"
        }
    }

    var symbolName: String {
        switch self {
        case .draftFromPrompt:
            return "text.badge.plus"
        case .shortcut(let action, _):
            return action.symbolName
        case .draftReply:
            return "arrowshape.turn.up.left"
        case .suggestSubject:
            return "textformat.size"
        }
    }

    var scope: ComposeAIActionScope {
        switch self {
        case .draftFromPrompt:
            return .prompt
        case .shortcut(_, let scope):
            return scope
        case .draftReply:
            return .replyContext
        case .suggestSubject:
            return .subject
        }
    }

    var requirements: Set<ComposeAIActionRequirement> {
        switch self {
        case .draftFromPrompt:
            return [.promptText]
        case .shortcut(_, let scope):
            switch scope {
            case .wholeDraft:
                return [.bodyText]
            case .selection:
                return [.selectedText]
            case .prompt, .replyContext, .subject:
                return []
            }
        case .draftReply:
            return [.replyContext]
        case .suggestSubject:
            return [.bodyText, .subjectTarget]
        }
    }

    var shortcutAction: AIShortcutAction? {
        guard case .shortcut(let action, _) = self else { return nil }
        return action
    }
}

enum ComposeAIActionScope: String, Equatable, Sendable {
    case wholeDraft
    case selection
    case prompt
    case replyContext
    case subject
}

enum ComposeAIActionRequirement: Hashable, Sendable {
    case bodyText
    case selectedText
    case promptText
    case replyContext
    case subjectTarget
}

struct ComposeAIActionContext: Equatable, Sendable {
    var hasBackend: Bool
    var isEnabled: Bool
    var hasConsent: Bool
    var supportsAI: Bool
    var isBusy: Bool
    var hasActiveRequest: Bool
    var bodyText: String
    var selectedText: String?
    var promptText: String?
    var hasReplyContext: Bool
    var hasSubjectTarget: Bool
}

enum ComposeAIActionDisabledReason: Equatable, Sendable {
    case missingBackend
    case notEnabled
    case consentRequired
    case unsupportedAccount
    case busy
    case requestInFlight
    case bodyTextRequired
    case selectedTextRequired
    case promptRequired
    case replyContextRequired
    case subjectTargetRequired

    var title: String {
        switch self {
        case .missingBackend:
            return "AI Writer is unavailable for this compose window."
        case .notEnabled:
            return "AI Writer is turned off."
        case .consentRequired:
            return "AI Writer needs consent before sending text."
        case .unsupportedAccount:
            return "This account does not support AI Writer."
        case .busy:
            return "Finish the current compose action first."
        case .requestInFlight:
            return "AI Writer is already working."
        case .bodyTextRequired:
            return "Write draft text before using this action."
        case .selectedTextRequired:
            return "Select text before using this action."
        case .promptRequired:
            return "Enter a prompt before using this action."
        case .replyContextRequired:
            return "Open this from a reply compose window."
        case .subjectTargetRequired:
            return "Open a compose window with an editable subject."
        }
    }
}

enum ComposeAIActionAvailability {
    static func disabledReason(
        for action: ComposeAIAction,
        in context: ComposeAIActionContext
    ) -> ComposeAIActionDisabledReason? {
        if !context.supportsAI { return .unsupportedAccount }
        if !context.hasBackend { return .missingBackend }
        if !context.isEnabled { return .notEnabled }
        if !context.hasConsent { return .consentRequired }
        if context.isBusy { return .busy }
        if context.hasActiveRequest { return .requestInFlight }
        if action.requirements.contains(.bodyText), isBlank(context.bodyText) {
            return .bodyTextRequired
        }
        if action.requirements.contains(.selectedText), isBlank(context.selectedText) {
            return .selectedTextRequired
        }
        if action.requirements.contains(.promptText), isBlank(context.promptText) {
            return .promptRequired
        }
        if action.requirements.contains(.replyContext), !context.hasReplyContext {
            return .replyContextRequired
        }
        if action.requirements.contains(.subjectTarget), !context.hasSubjectTarget {
            return .subjectTargetRequired
        }
        return nil
    }

    private static func isBlank(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }
}
