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

/// The reply/forward quote inputs a `ComposeView` needs, derived from a
/// compose payload and its resolved header.
struct DetachedComposeQuoteContext: Equatable {
    let replyingTo: MessageHeader?
    let replyMode: ComposeReplyMode
    let forwardingFrom: MessageHeader?
}

/// Pure derivations a detached compose window needs from its id-only
/// `ComposeWindowPayload` (ADR-0033). Kept out of the `#if os(iOS)`
/// `DetachedComposeWindowView` so the logic is host-testable.
enum DetachedComposeInputs {
    /// The referenced message id for reply/forward payloads, `nil` for `.new`.
    static func messageID(for kind: ComposeWindowPayload.Kind) -> String? {
        switch kind {
        case .new:
            return nil
        case .reply(let messageID, _),
             .replyAll(let messageID, _),
             .forward(let messageID, _):
            return messageID
        }
    }

    /// The source mailbox of the referenced message for reply/forward payloads,
    /// `nil` for a new message (which has no originating mailbox).
    static func sourceID(for kind: ComposeWindowPayload.Kind) -> MailSourceID? {
        switch kind {
        case .new(let sourceID):
            return sourceID
        case .reply(_, let sourceID),
             .replyAll(_, let sourceID),
             .forward(_, let sourceID):
            return sourceID
        }
    }

    /// Whether a previously-saved new-message recovery snapshot should be
    /// restored on open.
    ///
    /// Mirrors the sheet path, which only restores recovery for a brand-new
    /// compose — `ComposeDraftRecoverySnapshot.recoverableNewMessageDraft`
    /// never produces a snapshot for reply or forward drafts, so loading one
    /// for those kinds would be meaningless.
    static func restoresRecoverySnapshot(for kind: ComposeWindowPayload.Kind) -> Bool {
        if case .new = kind {
            return true
        }
        return false
    }

    /// Maps a payload kind and its resolved header onto the reply/forward quote
    /// inputs `ComposeView` expects: reply and reply-all quote `header` (with
    /// the matching `ComposeReplyMode`), forward attaches `header` as the
    /// forwarded message, and a new message carries no quote.
    static func quoteContext(
        for kind: ComposeWindowPayload.Kind,
        header: MessageHeader?
    ) -> DetachedComposeQuoteContext {
        switch kind {
        case .new:
            return DetachedComposeQuoteContext(replyingTo: nil, replyMode: .sender, forwardingFrom: nil)
        case .reply:
            return DetachedComposeQuoteContext(replyingTo: header, replyMode: .sender, forwardingFrom: nil)
        case .replyAll:
            return DetachedComposeQuoteContext(replyingTo: header, replyMode: .all, forwardingFrom: nil)
        case .forward:
            return DetachedComposeQuoteContext(replyingTo: nil, replyMode: .sender, forwardingFrom: header)
        }
    }
}
