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

enum ComposeOperationKind: Sendable {
    case send
    case saveDraft
    case autoSaveDraft
}

struct ComposeOperationSnapshot: Equatable, Sendable {
    let senderID: String?
    let identityID: String?
    let to: [String]
    let cc: [String]
    let bcc: [String]
    let subject: String
    let bodyText: String
    let attachmentIDs: [UUID]

    init(
        senderID: String? = nil,
        identityID: String? = nil,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        bodyText: String,
        attachmentIDs: [UUID]
    ) {
        self.senderID = senderID
        self.identityID = identityID
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.attachmentIDs = attachmentIDs
    }
}

struct ComposeOperationRequest: Equatable, Sendable {
    let id: Int
    let kind: ComposeOperationKind
    let snapshot: ComposeOperationSnapshot
}

enum ComposeOperationStartPolicy {
    static func canStartOperation(
        requestedKind: ComposeOperationKind = .send,
        isInteractionBusy: Bool,
        isBlocked: Bool,
        activeRequest: ComposeOperationRequest?
    ) -> Bool {
        guard !isBlocked, !isInteractionBusy else { return false }
        guard let activeRequest else { return true }
        return requestedKind == .send && activeRequest.kind == .autoSaveDraft
    }
}

enum ComposeOperationResponsePolicy {
    /// Whether the result of a completed compose operation should be applied
    /// (run completion + close the composer).
    ///
    /// The operation must still be the active one — otherwise it was superseded
    /// or the composer was torn down. For an *implicit* autosave we additionally
    /// require the content to be unchanged, so a slow autosave never clobbers
    /// edits the user made while it was in flight. For *explicit* user actions
    /// (`.send`, `.saveDraft`) the action already happened — the message was
    /// sent, the draft was written — so we must always finalize regardless of
    /// incidental content drift (signature insertion, body normalization, or the
    /// editor committing text on resign-first-responder). Gating those on
    /// snapshot equality is what previously left the composer window stuck open
    /// after a successful send and skipped the post-send mailbox refresh.
    static func canApplyResponse(
        request: ComposeOperationRequest,
        activeRequest: ComposeOperationRequest?,
        currentSnapshot: ComposeOperationSnapshot
    ) -> Bool {
        guard activeRequest == request else { return false }
        switch request.kind {
        case .autoSaveDraft:
            return currentSnapshot == request.snapshot
        case .send, .saveDraft:
            return true
        }
    }
}

enum ComposeSendDraftPersistencePolicy {
    static func shouldPersistDraftBeforeSend(hasPendingAttachments: Bool) -> Bool {
        hasPendingAttachments
    }
}
