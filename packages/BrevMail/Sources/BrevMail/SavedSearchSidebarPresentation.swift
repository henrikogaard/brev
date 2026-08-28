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

import BrevSettings
import Foundation

struct SavedSearchSidebarRow: Equatable, Identifiable, Sendable {
    let id: SmartMailbox.ID
    let title: String
    let symbolName: String
    let kind: SmartMailboxKind
}

enum SavedSearchSidebarPresentation {
    static func rows(from mailboxes: [SmartMailbox]) -> [SavedSearchSidebarRow] {
        mailboxes
            .filter(\.isEnabled)
            .map { mailbox in
                SavedSearchSidebarRow(
                    id: mailbox.id,
                    title: mailbox.name,
                    symbolName: mailbox.kind == .attachmentSearch ? "paperclip" : "magnifyingglass",
                    kind: mailbox.kind
                )
            }
    }

    static func shouldLeaveSelection(
        selectedID: SmartMailbox.ID?,
        mailboxes: [SmartMailbox]
    ) -> Bool {
        guard let selectedID else { return false }
        return !mailboxes.contains { $0.id == selectedID && $0.isEnabled }
    }
}
