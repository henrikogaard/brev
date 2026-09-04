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

/// Mailbox identity and cached folders shared by Mail and Settings.
public struct SettingsMailbox: Equatable, Sendable, Identifiable {
    public let account: BrevAccount
    public let mailbox: Mailbox
    public let folders: [Folder]
    public var id: MailSourceID { MailSourceID(accountID: account.id, mailboxID: mailbox.id) }

    /// Creates an explicit mailbox choice without loading a provider again.
    public init(account: BrevAccount, mailbox: Mailbox, folders: [Folder]) {
        self.account = account
        self.mailbox = mailbox
        self.folders = folders
    }
}

/// The mail workspace's current selection and available mailbox choices.
public struct SettingsMailboxContext: Equatable, Sendable {
    public let selectedSourceID: MailSourceID?
    public let mailboxes: [SettingsMailbox]

    /// Creates a context from the visible mail workspace.
    public init(selectedSourceID: MailSourceID? = nil, mailboxes: [SettingsMailbox] = []) {
        self.selectedSourceID = selectedSourceID
        self.mailboxes = mailboxes
    }

    /// Follows a new Mail selection while retaining deliberate Settings choices during refresh.
    public func selection(replacing previous: Self, current: MailSourceID?) -> MailSourceID? {
        if selectedSourceID != previous.selectedSourceID { return selectedSourceID }
        return current ?? selectedSourceID
    }
}
