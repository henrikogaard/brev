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

/// Inputs needed to resolve mailbox chat scope chips and search behavior.
struct MailboxChatScopeContext: Equatable, Sendable {
    var senderEmail: String?
    var folder: Folder?
    var accountLabel: String?
    var sourceID: MailSourceID?

    var defaultChipKind: MailboxChatScopeChipKind {
        if senderEmail != nil {
            return .sender
        }
        if folder != nil {
            return .folder
        }
        if sourceID != nil {
            return .account
        }
        return .sender
    }

    func isChipEnabled(_ kind: MailboxChatScopeChipKind) -> Bool {
        switch kind {
        case .sender:
            return senderEmail != nil
        case .folder:
            return folder != nil
        case .account:
            return sourceID != nil
        }
    }

    func scope(for chip: MailboxChatScopeChipKind) -> MailboxChatScope? {
        switch chip {
        case .sender:
            guard let senderEmail else { return nil }
            return .sender(email: senderEmail)
        case .folder:
            guard folder != nil else { return nil }
            return .folder
        case .account:
            guard sourceID != nil else { return nil }
            return .account
        }
    }

    func chipTitle(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender:
            senderEmail ?? String(localized: "Sender", bundle: .module)
        case .folder:
            folder?.name ?? String(localized: "Folder", bundle: .module)
        case .account:
            String(localized: "All folders", bundle: .module)
        }
    }

    /// Compact chip caption: full addresses get clipped mid-domain in the
    /// narrow column, so the sender chip carries the local part while the
    /// complete address stays on the accessibility label.
    func chipShortTitle(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender:
            guard let senderEmail else { return chipTitle(for: kind) }
            return senderEmail.split(separator: "@").first.map(String.init)
                ?? senderEmail
        case .folder, .account:
            return chipTitle(for: kind)
        }
    }

    func chipAccessibilityLabel(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender, .folder:
            return chipTitle(for: kind)
        case .account:
            if let accountLabel {
                return String(localized: "All folders in \(accountLabel)", bundle: .module)
            }
            return String(localized: "All folders", bundle: .module)
        }
    }

    /// Tooltip on a disabled chip explaining what unlocks it — without it the
    /// dimming reads as broken rather than as "not applicable here".
    func chipDisabledHelp(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender:
            String(localized: "Select a message to search its sender.", bundle: .module)
        case .folder:
            String(localized: "Open a single folder to scope the search.", bundle: .module)
        case .account:
            String(localized: "View a single account to search all its folders.", bundle: .module)
        }
    }
}

/// Builds cache-only search queries for mailbox chat Q&A by scope.
enum MailboxChatScopeSearchPolicy {
    static func answerSearchQuery(
        question: String,
        scope: MailboxChatScope,
        folderID: String?
    ) -> SearchQuery {
        switch scope {
        case .sender(let email):
            return SearchQuery(text: question, from: email, execution: .cacheOnly)
        case .folder:
            return SearchQuery(text: question, folderID: folderID, execution: .cacheOnly)
        case .account:
            return SearchQuery(text: question, execution: .cacheOnly)
        }
    }

    static func emptySearchMessage(
        scope: MailboxChatScope,
        folderName: String?
    ) -> String {
        switch scope {
        case .sender(let email):
            return String(
                localized: "I couldn't find cached messages from \(email) that answer that yet.",
                bundle: .module
            )
        case .folder:
            let name = folderName ?? String(localized: "this folder", bundle: .module)
            return String(
                localized: "I couldn't find cached messages in \(name) that answer that yet.",
                bundle: .module
            )
        case .account:
            return String(
                localized: "I couldn't find cached messages across this account's folders that answer that yet.",
                bundle: .module
            )
        }
    }

    static func scopeDescription(
        scope: MailboxChatScope,
        folderName: String?,
        accountLabel: String?
    ) -> String {
        switch scope {
        case .sender(let email):
            email
        case .folder:
            folderName ?? String(localized: "current folder", bundle: .module)
        case .account:
            accountLabel.map { String(localized: "all folders in \($0)", bundle: .module) }
                ?? String(localized: "all folders in the current account", bundle: .module)
        }
    }
}
