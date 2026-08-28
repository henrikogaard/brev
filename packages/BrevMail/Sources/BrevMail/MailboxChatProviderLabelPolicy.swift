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

/// Transparency labels shown on mailbox chat assistant turns.
enum MailboxChatProviderLabelPolicy {
    static let mailboxChat = "Mailbox chat"

    static func localClarification() -> String {
        mailboxChat
    }

    static func localError() -> String {
        mailboxChat
    }

    static func actionPlanner() -> String {
        MailboxChatController.localActionProviderLabel
    }

    static func aiError(backend: (any AIBackend)?) -> String {
        backend?.transparencyLabel ?? mailboxChat
    }
}
