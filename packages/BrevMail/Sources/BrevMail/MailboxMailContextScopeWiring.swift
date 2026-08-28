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
import Foundation

/// Wires mailbox chat scope inputs the same way `BrevMailRootView` and
/// `MailContextColumn` pass them into `MailboxChatPanel`.
enum MailboxMailContextScopeWiring {
    /// Builds the mailbox action scope for the selected source section.
    static func actionSourceScope(
        sourceID: MailSourceID?,
        sourceSections: [MailSourceSection]
    ) -> MailboxActionAgentSourceScope {
        let section = sourceID.flatMap { id in
            sourceSections.first { $0.id == id }
        }
        return MailboxActionSourceScopePolicy.make(sourceID: sourceID, section: section)
    }

    /// Builds mailbox chat chip context from inspector inputs.
    static func chatScopeContext(
        mailboxChatScope: MailboxChatScope,
        sourceID: MailSourceID?,
        focusedFolder: Folder?,
        actionSourceScope: MailboxActionAgentSourceScope
    ) -> MailboxChatScopeContext {
        MailboxChatScopeContext(
            senderEmail: senderEmail(from: mailboxChatScope),
            folder: focusedFolder,
            accountLabel: accountChipLabel(
                sourceID: sourceID,
                actionSourceScope: actionSourceScope
            ),
            sourceID: sourceID
        )
    }

    private static func senderEmail(from scope: MailboxChatScope) -> String? {
        if case .sender(let email) = scope {
            return email
        }
        return nil
    }

    private static func accountChipLabel(
        sourceID: MailSourceID?,
        actionSourceScope: MailboxActionAgentSourceScope
    ) -> String? {
        guard sourceID != nil else { return nil }
        if let mailboxName = actionSourceScope.mailboxName {
            return mailboxName
        }
        if let accountName = actionSourceScope.accountName {
            return accountName
        }
        if let mailboxAddress = actionSourceScope.mailboxAddress {
            return mailboxAddress
        }
        return "Account"
    }
}
