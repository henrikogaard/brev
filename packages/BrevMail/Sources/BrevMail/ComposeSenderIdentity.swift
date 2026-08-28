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
        defaultSourceID: MailSourceID?
    ) -> ComposeSenderOption? {
        let preferredSourceIDs = [selectedSourceID, defaultSourceID].compactMap { $0 }
        for sourceID in preferredSourceIDs {
            if let option = options.first(where: { $0.sourceID == sourceID }) {
                return option
            }
        }
        return options.first
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
    static func resolution(
        from sections: [MailSourceSection],
        fallbackAccount: BrevAccount,
        selectedSourceID: MailSourceID?,
        defaultSourceID: MailSourceID?
    ) -> ComposeSenderResolution {
        let options = senderOptions(from: sections, fallbackAccount: fallbackAccount)
        let initialSender = preferredSender(
            from: options,
            selectedSourceID: selectedSourceID,
            defaultSourceID: defaultSourceID
        )
        return ComposeSenderResolution(
            options: options,
            initialSender: initialSender,
            sourceID: initialSender?.sourceID ?? selectedSourceID
        )
    }
}
