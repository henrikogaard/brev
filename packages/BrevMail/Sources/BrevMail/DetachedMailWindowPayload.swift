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

/// Identifies a message to open in a detached reader window. State is
/// reconstructed from these ids inside the new scene (the scene has no
/// in-memory parent state).
public struct DetachedReaderWindowPayload: Codable, Hashable, Sendable {
    /// The mailbox source containing the message, or `nil` when the source
    /// context is not yet known (e.g. a universal link opened before sign-in).
    public let sourceID: MailSourceID?
    /// The backend message identifier.
    public let messageID: String

    public init(sourceID: MailSourceID?, messageID: String) {
        self.sourceID = sourceID
        self.messageID = messageID
    }
}

/// Identifies a compose intent to open in a detached compose window.
public struct ComposeWindowPayload: Codable, Hashable, Sendable {
    /// The intended compose action.
    public enum Kind: Codable, Hashable, Sendable {
        /// Open a blank compose window for the given account/mailbox source
        /// (so the detached window composes from the selected account, not just
        /// the first backend). `nil` leaves account selection to the resolver.
        ///
        /// Because the payload is the `WindowGroup(for:)` value, window identity
        /// is intentionally per-source: a second "New Message" while a different
        /// account is selected opens a distinct window (composing as that
        /// account) rather than raising the first window in the wrong account.
        /// Two "New Message" taps under the *same* selected source still coalesce.
        case new(sourceID: MailSourceID?)
        /// Reply to a specific message.
        case reply(messageID: String, sourceID: MailSourceID?)
        /// Reply-all to a specific message.
        case replyAll(messageID: String, sourceID: MailSourceID?)
        /// Forward a specific message.
        case forward(messageID: String, sourceID: MailSourceID?)
    }

    public let kind: Kind

    public init(kind: Kind) { self.kind = kind }
}
