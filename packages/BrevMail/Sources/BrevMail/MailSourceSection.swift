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

public struct MailSourceSection: Identifiable, Equatable, Sendable {
    public let id: MailSourceID
    public let account: BrevAccount
    public let mailbox: Mailbox
    public let folders: [Folder]
    public let loadError: FolderLoadError?

    public init(
        id: MailSourceID,
        account: BrevAccount,
        mailbox: Mailbox,
        folders: [Folder],
        loadError: FolderLoadError? = nil
    ) {
        self.id = id
        self.account = account
        self.mailbox = mailbox
        self.folders = folders
        self.loadError = loadError
    }

    public var title: String {
        mailbox.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? mailbox.email
            : mailbox.displayName
    }

    public var subtitle: String {
        if mailbox.email != title {
            return mailbox.email
        }
        return account.backendDisplayName
    }
}
