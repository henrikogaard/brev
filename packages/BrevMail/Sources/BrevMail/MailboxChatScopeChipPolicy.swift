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

enum MailboxChatScopeChipKind: String, Equatable, Sendable, CaseIterable {
    case sender
    case folder
    case account
}

struct MailboxChatScopeChip: Equatable, Identifiable, Sendable {
    var id: MailboxChatScopeChipKind { kind }

    let kind: MailboxChatScopeChipKind
    let title: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let isSelected: Bool
}

/// Builds the mailbox chat scope chip row for the current scope.
enum MailboxChatScopeChipPolicy {
    static func chips(
        context: MailboxChatScopeContext,
        selected: MailboxChatScopeChipKind
    ) -> [MailboxChatScopeChip] {
        MailboxChatScopeChipKind.allCases.map { kind in
            MailboxChatScopeChip(
                kind: kind,
                title: context.chipTitle(for: kind),
                accessibilityLabel: context.chipAccessibilityLabel(for: kind),
                isEnabled: context.isChipEnabled(kind),
                isSelected: selected == kind
            )
        }
    }
}
