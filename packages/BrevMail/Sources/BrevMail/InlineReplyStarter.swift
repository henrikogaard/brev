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

import Foundation

/// A one-click way to start the docked reply with AI Writer (#302): a preset
/// intent, or the user's own description of the reply. Runs only on click,
/// through the same consent and preview flow as the AI Writer menu.
enum InlineReplyStarter: Equatable, Sendable {
    case reply
    case sayYes
    case declinePolitely
    case askForMoreTime
    case askAQuestion
    case described(String)

    /// The preset starters, in the order the dock shows them.
    static let presets: [InlineReplyStarter] = [.reply, .sayYes, .declinePolitely, .askForMoreTime, .askAQuestion]

    /// Stable key for identity and accessibility.
    var key: String {
        switch self {
        case .reply: "reply"
        case .sayYes: "sayYes"
        case .declinePolitely: "declinePolitely"
        case .askForMoreTime: "askForMoreTime"
        case .askAQuestion: "askAQuestion"
        case .described: "described"
        }
    }

    /// The chip or preview title.
    var title: String {
        switch self {
        case .reply: String(localized: "Reply", bundle: .module)
        case .sayYes: String(localized: "Say yes", bundle: .module)
        case .declinePolitely: String(localized: "Decline politely", bundle: .module)
        case .askForMoreTime: String(localized: "Ask for more time", bundle: .module)
        case .askAQuestion: String(localized: "Ask a question", bundle: .module)
        case .described: String(localized: "Draft Reply", bundle: .module)
        }
    }

    var symbolName: String {
        switch self {
        case .reply, .described: "arrowshape.turn.up.left"
        case .sayYes: "checkmark"
        case .declinePolitely: "xmark"
        case .askForMoreTime: "clock"
        case .askAQuestion: "questionmark"
        }
    }

    /// The intent sent to the AI provider, in English like the rest of the
    /// AI Writer prompts; nil when the reply context alone is enough.
    var guidance: String? {
        switch self {
        case .reply: nil
        case .sayYes: "Say yes."
        case .declinePolitely: "Decline politely."
        case .askForMoreTime: "Ask for more time."
        case .askAQuestion: "Ask a clarifying question."
        case .described(let text):
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Starters show only in the docked reply, and only while AI Writer is
    /// on, consented and backed by a provider for this account; otherwise
    /// they are hidden, not disabled.
    static func isVisible(
        isInline: Bool,
        hasReplyContext: Bool,
        availability: ComposeAIAvailabilityState
    ) -> Bool {
        isInline
            && hasReplyContext
            && availability.settings.isAvailable
            && availability.providerUnavailableReason == nil
    }
}
