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

struct ComposeSenderOption: Identifiable, Equatable, Hashable, Sendable {
    let sourceID: MailSourceID?
    let accountID: BrevAccount.ID
    let displayName: String?
    let email: String
    let subtitle: String

    var id: String {
        if let sourceID {
            return "\(sourceID.accountID):\(sourceID.mailboxID)"
        }
        return "\(accountID):fallback:\(email.lowercased())"
    }

    var title: String {
        guard let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty
        else {
            return email
        }
        return displayName
    }

    var correspondent: Correspondent {
        Correspondent(name: displayName, email: email)
    }
}

/// The resolved "From:" inputs for a compose surface: every selectable sender
/// option, the initial selection, and the effective source id the draft is
/// keyed to (used for draft staging and recovery).
struct ComposeSenderResolution: Equatable {
    let options: [ComposeSenderOption]
    let initialSender: ComposeSenderOption?
    let sourceID: MailSourceID?
}

/// Separates the account/source that owns the original message (for quoted body
/// retrieval) from the recipient-matched sending source across quick-reply dock
/// expansion and full compose presentation.
struct ComposeReplyAccountRouting: Equatable, Sendable {
    let sendingSourceID: MailSourceID?
    let quotedMessageSourceID: MailSourceID?

    static func resolve(
        replyingTo header: MessageHeader?,
        in sections: [MailSourceSection],
        messageOwnerSourceID: MailSourceID?,
        defaultSourceID: MailSourceID?
    ) -> ComposeReplyAccountRouting {
        let matchedSendingSourceID: MailSourceID? = if let header {
            ComposeSenderIdentity.replySourceID(
                for: header,
                in: sections,
                selectedSourceID: messageOwnerSourceID,
                defaultSourceID: defaultSourceID
            )
        } else {
            messageOwnerSourceID
        }
        return ComposeReplyAccountRouting(
            sendingSourceID: matchedSendingSourceID ?? messageOwnerSourceID ?? defaultSourceID,
            quotedMessageSourceID: messageOwnerSourceID ?? defaultSourceID
        )
    }
}

enum ComposeSenderIdentity {
    static func senderSections(
        from sourceSections: [MailSourceSection],
        selectedSourceID: MailSourceID?,
        defaultSourceID: MailSourceID?,
        fallbackAccountID: BrevAccount.ID
    ) -> [MailSourceSection] {
        let preferredSourceIDs = [selectedSourceID, defaultSourceID].compactMap { $0 }
        for sourceID in preferredSourceIDs {
            if let section = sourceSections.first(where: { $0.id == sourceID }) {
                return sourceSections.filter { $0.account.id == section.account.id }
            }
        }

        let fallbackSections = sourceSections.filter { $0.account.id == fallbackAccountID }
        if !fallbackSections.isEmpty {
            return fallbackSections
        }
        return sourceSections
    }

    static func sender(
        account: BrevAccount,
        mailboxes: [Mailbox],
        activeMailboxID: Mailbox.ID?
    ) -> Correspondent {
        if let activeMailboxID,
           let mailbox = mailboxes.first(where: { $0.id == activeMailboxID }) {
            return Correspondent(name: mailbox.displayName, email: mailbox.email)
        }
        return Correspondent(name: account.displayName, email: account.emailAddress)
    }

    static func senderOptions(
        from sourceSections: [MailSourceSection],
        fallbackAccount: BrevAccount
    ) -> [ComposeSenderOption] {
        let options = sourceSections.map { section in
            ComposeSenderOption(
                sourceID: section.id,
                accountID: section.account.id,
                displayName: section.mailbox.displayName,
                email: section.mailbox.email,
                subtitle: section.subtitle
            )
        }
        guard options.isEmpty else { return options }
        return [
            ComposeSenderOption(
                sourceID: nil,
                accountID: fallbackAccount.id,
                displayName: fallbackAccount.displayName,
                email: fallbackAccount.emailAddress,
                subtitle: fallbackAccount.backendDisplayName
            )
        ]
    }

    static func preferredSender(
        from options: [ComposeSenderOption],
        selectedSourceID: MailSourceID?,
        defaultSourceID: MailSourceID?,
        replyingTo: MessageHeader? = nil
    ) -> ComposeSenderOption? {
        if let replyingTo,
           let matched = matchedReplyOption(
               for: replyingTo,
               in: options,
               preferredSourceID: selectedSourceID
           ) {
            return matched
        }
        let preferredSourceIDs = [selectedSourceID, defaultSourceID].compactMap { $0 }
        for sourceID in preferredSourceIDs {
            if let option = options.first(where: { $0.sourceID == sourceID }) {
                return option
            }
        }
        return options.first
    }

    /// Resolves the source section to reply from for `header`. Prefers a section
    /// whose mailbox address appears in `header.to`, then `header.cc` (breaking
    /// ties with `selectedSourceID` when multiple own identities were addressed),
    /// before falling back to `selectedSourceID`, `defaultSourceID`, or the first
    /// available section.
    static func replySourceID(
        for header: MessageHeader,
        in sections: [MailSourceSection],
        selectedSourceID: MailSourceID?,
        defaultSourceID: MailSourceID?
    ) -> MailSourceID? {
        if let matched = matchedReplySection(
            for: header,
            in: sections,
            preferredSourceID: selectedSourceID
        ) {
            return matched.id
        }
        let preferredSourceIDs = [selectedSourceID, defaultSourceID].compactMap { $0 }
        for sourceID in preferredSourceIDs {
            if sections.contains(where: { $0.id == sourceID }) {
                return sourceID
            }
        }
        return selectedSourceID ?? defaultSourceID ?? sections.first?.id
    }

    /// Resolves the sender options, initial selection, and effective source id
    /// for a compose surface from a single account's source sections.
    ///
    /// Shared by the sheet path (`BrevMailRootView`) and the detached compose
    /// window (`DetachedComposeWindowView`) so both resolve the multi-identity
    /// "From:" selection identically. `sections` should already be scoped to
    /// the composing account.
    ///
    /// - Parameters:
    ///   - sections: The composing account's mailbox source sections.
    ///   - fallbackAccount: Used to synthesize a single option when `sections`
    ///     is empty.
    ///   - selectedSourceID: The source the user is composing from, if any.
    ///   - defaultSourceID: The account's default source, used when nothing is
    ///     explicitly selected.
    ///   - replyingTo: Optional message header being replied to; when present,
    ///     an option matching its addressed recipient takes precedence.
    static func resolution(
        from sections: [MailSourceSection],
        fallbackAccount: BrevAccount,
        selectedSourceID: MailSourceID?,
        defaultSourceID: MailSourceID?,
        replyingTo: MessageHeader? = nil
    ) -> ComposeSenderResolution {
        let options = senderOptions(from: sections, fallbackAccount: fallbackAccount)
        let initialSender = preferredSender(
            from: options,
            selectedSourceID: selectedSourceID,
            defaultSourceID: defaultSourceID,
            replyingTo: replyingTo
        )
        return ComposeSenderResolution(
            options: options,
            initialSender: initialSender,
            sourceID: initialSender?.sourceID ?? selectedSourceID
        )
    }

    private static func matchedReplySection(
        for header: MessageHeader,
        in sections: [MailSourceSection],
        preferredSourceID: MailSourceID?
    ) -> MailSourceSection? {
        for recipients in [header.to, header.cc] {
            let recipientEmails = Set(recipients.map { normalizedEmail($0.email) }.filter { !$0.isEmpty })
            guard !recipientEmails.isEmpty else { continue }
            let matches = sections.filter { recipientEmails.contains(normalizedEmail($0.mailbox.email)) }
            guard !matches.isEmpty else { continue }
            if let preferredSourceID,
               let preferred = matches.first(where: { $0.id == preferredSourceID }) {
                return preferred
            }
            return matches.first
        }
        return nil
    }

    private static func matchedReplyOption(
        for header: MessageHeader,
        in options: [ComposeSenderOption],
        preferredSourceID: MailSourceID?
    ) -> ComposeSenderOption? {
        for recipients in [header.to, header.cc] {
            let recipientEmails = Set(recipients.map { normalizedEmail($0.email) }.filter { !$0.isEmpty })
            guard !recipientEmails.isEmpty else { continue }
            let matches = options.filter { recipientEmails.contains(normalizedEmail($0.email)) }
            guard !matches.isEmpty else { continue }
            if let preferredSourceID,
               let preferred = matches.first(where: { $0.sourceID == preferredSourceID }) {
                return preferred
            }
            return matches.first
        }
        return nil
    }

    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
