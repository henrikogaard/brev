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

/// Resolves the mailbox-chat scope for the Mail Context surface.
///
/// Shared by the macOS trailing column and the iOS sheet so both present the
/// same conversation context: the selected message's sender when one is
/// selected, the focused folder otherwise, and the account as the fallback.
enum MailContextColumnScopePolicy {
    static func chatScope(
        selectedHeader: MessageHeader?,
        focusedFolder: Folder?
    ) -> MailboxChatScope {
        if let senderEmail = selectedHeader?.from.email.trimmingCharacters(in: .whitespacesAndNewlines),
           !senderEmail.isEmpty {
            return .sender(email: senderEmail)
        }
        if focusedFolder != nil {
            return .folder
        }
        return .account
    }
}
