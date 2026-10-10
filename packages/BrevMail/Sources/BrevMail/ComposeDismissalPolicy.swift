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

import Foundation

/// The user-visible parts of a compose session that decide whether closing it
/// would lose work. The quoted original and the managed signature are left out
/// so an untouched reply or forward still counts as clean.
struct ComposeDismissalContent: Equatable {
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var userBody: String
    var attachmentCount: Int

    /// An empty compose: the baseline for new messages, recovered drafts and
    /// `mailto:` prefills, which exist nowhere on the server yet.
    static let blank = ComposeDismissalContent(
        to: [],
        cc: [],
        bcc: [],
        subject: "",
        userBody: "",
        attachmentCount: 0
    )

    /// Whitespace and recipient separators are normalised so a stray space or
    /// newline never counts as an edit.
    fileprivate var normalized: ComposeDismissalContent {
        ComposeDismissalContent(
            to: ComposeDraftBuilder.recipientAddresses(from: to),
            cc: ComposeDraftBuilder.recipientAddresses(from: cc),
            bcc: ComposeDraftBuilder.recipientAddresses(from: bcc),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            userBody: userBody.trimmingCharacters(in: .whitespacesAndNewlines),
            attachmentCount: attachmentCount
        )
    }

    /// The part of `body` the user wrote: the managed signature and the
    /// read-only quoted original are cut out.
    static func userBody(
        from body: String,
        quoteProtection: ComposeQuoteProtection?,
        managedSignatureBody: String?
    ) -> String {
        let withoutSignature = ComposeSignatureBodyPolicy.body(
            removing: managedSignatureBody,
            from: body
        )
        guard let quoteProtection else { return withoutSignature }
        let storage = withoutSignature as NSString
        guard let quoteRange = ComposeQuoteEditGuard.protectedRange(
            in: storage,
            protection: quoteProtection
        ) else {
            return withoutSignature
        }
        return storage.replacingCharacters(in: quoteRange, with: "")
    }
}

/// Snapshot of the compose session fed to `ComposeDismissalPolicy`.
struct ComposeDismissalState: Equatable {
    var isDirty: Bool
    /// Sending, saving a draft or an AI action is in flight.
    var isBusy: Bool
    /// The undo-send countdown is running.
    var isUndoSendPending: Bool
    /// A send, save or discard already finished; closing is now plain cleanup.
    var hasCompletedExplicitOperation: Bool
}

/// What closing the compose sheet should do.
enum ComposeDismissalDecision: Equatable {
    /// Nothing to lose: close without touching the draft.
    case closeNow
    /// Unsaved work: ask "Delete Draft" or "Save Draft" first.
    case askDeleteOrSave
    /// A send or save is in flight; closing now would abandon it.
    case ignore
}

/// The Cancel / swipe-down policy for the compose sheet, modelled on iOS Mail:
/// a clean draft closes, a dirty one asks, and nothing closes mid-operation.
enum ComposeDismissalPolicy {
    /// Whether `current` differs from the state the session opened with.
    static func isDirty(current: ComposeDismissalContent, baseline: ComposeDismissalContent) -> Bool {
        current.normalized != baseline.normalized
    }

    /// The outcome of tapping Cancel.
    static func decision(for state: ComposeDismissalState) -> ComposeDismissalDecision {
        if state.isBusy || state.isUndoSendPending { return .ignore }
        if state.hasCompletedExplicitOperation || !state.isDirty { return .closeNow }
        return .askDeleteOrSave
    }

    /// Whether the sheet must refuse an interactive swipe-down dismissal.
    static func blocksInteractiveDismissal(for state: ComposeDismissalState) -> Bool {
        decision(for: state) != .closeNow
    }

    /// The outcome of a swipe-down that `interactiveDismissDisabled` blocked.
    /// It routes to the same choice as Cancel.
    static func decision(forAttemptedSwipeWith state: ComposeDismissalState) -> ComposeDismissalDecision {
        decision(for: state)
    }
}
