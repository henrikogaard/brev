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

/// Stable identity for one visible mailbox source in Brev.
///
/// Raw folder and message identifiers are only unique inside a backend
/// account/mailbox. Carry this value whenever UI or settings state can
/// span multiple accounts or mailboxes.
public struct MailSourceID: Sendable, Hashable, Identifiable, Codable {
    public let accountID: BrevAccount.ID
    public let mailboxID: Mailbox.ID

    public init(accountID: BrevAccount.ID, mailboxID: Mailbox.ID) {
        self.accountID = accountID
        self.mailboxID = mailboxID
    }

    public var id: Self { self }
}

/// Folder identity scoped to the mailbox source that owns it.
public struct SourceFolderID: Sendable, Hashable, Identifiable, Codable {
    public let sourceID: MailSourceID
    public let folderID: Folder.ID

    public init(sourceID: MailSourceID, folderID: Folder.ID) {
        self.sourceID = sourceID
        self.folderID = folderID
    }

    public var id: Self { self }
}

/// Message identity scoped to the mailbox source that owns it.
public struct SourceMessageID: Sendable, Hashable, Identifiable, Codable {
    public let sourceID: MailSourceID
    public let messageID: MessageHeader.ID

    public init(sourceID: MailSourceID, messageID: MessageHeader.ID) {
        self.sourceID = sourceID
        self.messageID = messageID
    }

    public var id: Self { self }
}
