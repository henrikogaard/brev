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

/// Builds mailbox action/chat source scope from the selected mail source section.
enum MailboxActionSourceScopePolicy {
    static func make(
        sourceID: MailSourceID?,
        section: MailSourceSection?
    ) -> MailboxActionAgentSourceScope {
        guard let sourceID else {
            return .currentMailbox
        }
        guard let section, section.id == sourceID else {
            return MailboxActionAgentSourceScope(
                sourceID: sourceID,
                accountName: nil,
                mailboxName: nil,
                mailboxAddress: nil
            )
        }

        let mailboxDisplayName = section.mailbox.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return MailboxActionAgentSourceScope(
            sourceID: sourceID,
            accountName: section.account.displayName,
            mailboxName: mailboxDisplayName.isEmpty ? nil : mailboxDisplayName,
            mailboxAddress: section.mailbox.email
        )
    }
}
