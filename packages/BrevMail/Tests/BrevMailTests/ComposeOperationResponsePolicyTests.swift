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

@testable import BrevMail
import Foundation
import Testing

@Suite("ComposeOperationResponsePolicy")
struct ComposeOperationResponsePolicyTests {
    @Test("compose operation can start when no compose work is active")
    func composeOperationCanStartWhenNoComposeWorkIsActive() {
        #expect(ComposeOperationStartPolicy.canStartOperation(
            isInteractionBusy: false,
            isBlocked: false,
            activeRequest: nil
        ))
    }

    @Test("compose operation cannot start while interaction is busy")
    func composeOperationCannotStartWhileInteractionIsBusy() {
        #expect(!ComposeOperationStartPolicy.canStartOperation(
            isInteractionBusy: true,
            isBlocked: false,
            activeRequest: nil
        ))
    }

    @Test("compose operation cannot start while root work is active")
    func composeOperationCannotStartWhileRootWorkIsActive() {
        #expect(!ComposeOperationStartPolicy.canStartOperation(
            isInteractionBusy: false,
            isBlocked: true,
            activeRequest: nil
        ))
    }

    @Test("compose operation cannot start while another operation is active")
    func composeOperationCannotStartWhileAnotherOperationIsActive() {
        let request = ComposeOperationRequest(
            id: 1,
            kind: .send,
            snapshot: Self.snapshot(subject: "Hello")
        )

        #expect(!ComposeOperationStartPolicy.canStartOperation(
            isInteractionBusy: false,
            isBlocked: false,
            activeRequest: request
        ))
    }

    @Test("send operation can supersede background autosave")
    func sendOperationCanSupersedeBackgroundAutosave() {
        let request = ComposeOperationRequest(
            id: 1,
            kind: .autoSaveDraft,
            snapshot: Self.snapshot(subject: "Hello")
        )

        #expect(ComposeOperationStartPolicy.canStartOperation(
            requestedKind: .send,
            isInteractionBusy: false,
            isBlocked: false,
            activeRequest: request
        ))
    }

    @Test("draft save cannot supersede background autosave")
    func draftSaveCannotSupersedeBackgroundAutosave() {
        let request = ComposeOperationRequest(
            id: 1,
            kind: .autoSaveDraft,
            snapshot: Self.snapshot(subject: "Hello")
        )

        #expect(!ComposeOperationStartPolicy.canStartOperation(
            requestedKind: .saveDraft,
            isInteractionBusy: false,
            isBlocked: false,
            activeRequest: request
        ))
    }

    @Test("matching active request and unchanged draft can apply compose operation response")
    func matchingActiveRequestAndUnchangedDraftCanApplyComposeOperationResponse() {
        let snapshot = Self.snapshot(subject: "Hello")
        let request = ComposeOperationRequest(
            id: 1,
            kind: .send,
            snapshot: snapshot
        )

        #expect(ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSnapshot: snapshot
        ))
    }

    @Test("changed request kind or missing request rejects stale compose operation response")
    func changedRequestKindOrMissingRequestRejectsStaleComposeOperationResponse() {
        let snapshot = Self.snapshot(subject: "Hello")
        let request = ComposeOperationRequest(
            id: 1,
            kind: .send,
            snapshot: snapshot
        )

        #expect(!ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: ComposeOperationRequest(
                id: 1,
                kind: .saveDraft,
                snapshot: snapshot
            ),
            currentSnapshot: snapshot
        ))
        #expect(!ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: ComposeOperationRequest(
                id: 2,
                kind: .send,
                snapshot: snapshot
            ),
            currentSnapshot: snapshot
        ))
        #expect(!ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentSnapshot: snapshot
        ))
    }

    @Test("edited draft rejects stale autosave response")
    func editedDraftRejectsStaleAutosaveResponse() {
        let snapshot = Self.snapshot(subject: "Hello")
        let request = ComposeOperationRequest(
            id: 1,
            kind: .autoSaveDraft,
            snapshot: snapshot
        )

        #expect(!ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSnapshot: Self.snapshot(subject: "Updated")
        ))
    }

    @Test("changed attachment rows reject stale autosave response")
    func changedAttachmentRowsRejectStaleAutosaveResponse() {
        let snapshot = Self.snapshot(subject: "Hello")
        let request = ComposeOperationRequest(
            id: 1,
            kind: .autoSaveDraft,
            snapshot: snapshot
        )

        #expect(!ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSnapshot: ComposeOperationSnapshot(
                to: snapshot.to,
                cc: snapshot.cc,
                bcc: snapshot.bcc,
                subject: snapshot.subject,
                bodyText: snapshot.bodyText,
                attachmentIDs: []
            )
        ))
    }

    @Test("changed sender rejects stale autosave response")
    func changedSenderRejectsStaleAutosaveResponse() {
        let snapshot = Self.snapshot(subject: "Hello", senderID: "account-1:personal")
        let request = ComposeOperationRequest(
            id: 1,
            kind: .autoSaveDraft,
            snapshot: snapshot
        )

        #expect(!ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSnapshot: Self.snapshot(subject: "Hello", senderID: "account-1:contact")
        ))
    }

    @Test("successful send finalizes even when content drifts mid-send")
    func successfulSendFinalizesEvenWhenContentDriftsMidSend() {
        // Regression guard: a successful send previously left the composer
        // window stuck open and skipped the post-send mailbox refresh whenever
        // the snapshot drifted during the network round trip (signature
        // insertion, body normalization, editor commit on resign). Explicit
        // sends must always finalize.
        let request = ComposeOperationRequest(
            id: 1,
            kind: .send,
            snapshot: Self.snapshot(subject: "Hello")
        )

        #expect(ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSnapshot: Self.snapshot(subject: "Hello with signature")
        ))
    }

    @Test("manual draft save finalizes even when content drifts")
    func manualDraftSaveFinalizesEvenWhenContentDrifts() {
        let request = ComposeOperationRequest(
            id: 1,
            kind: .saveDraft,
            snapshot: Self.snapshot(subject: "Hello")
        )

        #expect(ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSnapshot: Self.snapshot(subject: "Updated")
        ))
    }

    @Test("superseded explicit send response is still rejected")
    func supersededExplicitSendResponseIsStillRejected() {
        let request = ComposeOperationRequest(
            id: 1,
            kind: .send,
            snapshot: Self.snapshot(subject: "Hello")
        )

        // A different active request (composer torn down / superseded) must
        // still reject, regardless of kind.
        #expect(!ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentSnapshot: Self.snapshot(subject: "Hello")
        ))
    }

    @Test("plain sends do not require remote draft persistence before SMTP")
    func plainSendsDoNotRequireRemoteDraftPersistenceBeforeSMTP() {
        #expect(!ComposeSendDraftPersistencePolicy.shouldPersistDraftBeforeSend(
            hasPendingAttachments: false
        ))
    }

    @Test("attachment sends still persist first so attachment bytes are staged")
    func attachmentSendsStillPersistFirstSoAttachmentBytesAreStaged() {
        #expect(ComposeSendDraftPersistencePolicy.shouldPersistDraftBeforeSend(
            hasPendingAttachments: true
        ))
    }

    private static func snapshot(
        subject: String,
        senderID: String? = nil
    ) -> ComposeOperationSnapshot {
        ComposeOperationSnapshot(
            senderID: senderID,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: subject,
            bodyText: "Body",
            attachmentIDs: [attachmentID]
        )
    }

    private static let attachmentID = UUID()
}
