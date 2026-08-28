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

import BrevBackend
import BrevSettings
import Foundation

/// Builds a prefilled local-rule draft from a message, seeded with a
/// "Sender contains" condition for the message's sender and a safe,
/// non-destructive default action (Mark read). The user reviews and edits the
/// draft — e.g. switching the action to Move to folder — in the rule editor
/// before saving. Per ADR-0032 this creates a *local* rule; syncing it to a
/// ManageSieve server stays the separate, existing opt-in in Settings → Rules.
enum MessageRuleDraftBuilder {
    static func draft(for header: MessageHeader) -> LocalRuleEditorDraft {
        LocalRuleEditorDraft(rule: ServerRule(
            id: UUID().uuidString,
            name: ruleName(for: header),
            isEnabled: true,
            conditions: [.senderContains(header.from.email)],
            actions: [.markRead]
        ))
    }

    /// Names the rule after the sender's display name, falling back to the bare
    /// address when there is no name.
    private static func ruleName(for header: MessageHeader) -> String {
        let trimmedName = header.from.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? header.from.email
        return "Mail from \(label)"
    }
}
