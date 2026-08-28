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

struct MailRootStatus: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case info
        case success
        case warning
        case danger
    }

    let message: String
    let tone: Tone
    let actionTitle: String?

    init(
        message: String,
        tone: Tone = .danger,
        actionTitle: String? = nil
    ) {
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
    }
}

enum MailRootStatusRetryAction: Equatable, Sendable {
    case refreshSelectedFolder
    case refreshVisibleMail
    case loadFolders
    case loadMailboxes
    case switchMailbox(Mailbox.ID)

    static func next(
        mailboxSwitchRetryID: Mailbox.ID?,
        shouldRetryMailboxLoad: Bool,
        shouldRetryFolderLoad: Bool,
        isUnifiedInbox: Bool
    ) -> MailRootStatusRetryAction {
        if let mailboxSwitchRetryID {
            return .switchMailbox(mailboxSwitchRetryID)
        }
        if shouldRetryMailboxLoad {
            return .loadMailboxes
        }
        if shouldRetryFolderLoad {
            return .loadFolders
        }
        if isUnifiedInbox {
            return .refreshVisibleMail
        }
        return .refreshSelectedFolder
    }
}
