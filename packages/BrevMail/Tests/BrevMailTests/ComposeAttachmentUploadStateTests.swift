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
@testable import BrevMail
import Foundation
import Testing

@Suite("ComposeAttachmentUploadState")
struct ComposeAttachmentUploadStateTests {
    @Test("failed uploads stay on the same pending row with retry copy")
    func failedUploadsStayOnSamePendingRowWithRetryCopy() {
        let attachment = PendingAttachment(
            filename: "brief.pdf",
            mimeType: "application/pdf",
            data: Data("pdf".utf8)
        )

        let failed = ComposeAttachmentUploadState.markFailed(
            attachment,
            message: "Network error: offline"
        )

        #expect(failed.id == attachment.id)
        #expect(failed.filename == attachment.filename)
        #expect(failed.uploadErrorMessage == "Network error: offline")
        #expect(ComposeAttachmentUploadState.statusText(for: failed) == "Upload failed: Network error: offline")
        #expect(ComposeAttachmentUploadState.retryActionTitle(for: failed) == "Retry on Send")
    }

    @Test("successful uploads are not uploaded again after retry request")
    func successfulUploadsAreNotUploadedAgainAfterRetryRequest() {
        let first = PendingAttachment(
            filename: "sent.pdf",
            mimeType: "application/pdf",
            data: Data("sent".utf8)
        )
        let second = PendingAttachment(
            filename: "failed.pdf",
            mimeType: "application/pdf",
            data: Data("failed".utf8)
        )

        let uploaded = ComposeAttachmentUploadState.markUploaded(first, remoteID: "remote-1")
        let failed = ComposeAttachmentUploadState.markFailed(second, message: "timeout")
        let retrying = ComposeAttachmentUploadState.clearFailure(failed)

        #expect(ComposeAttachmentUploadState.attachmentsNeedingUpload([uploaded, failed]).isEmpty)
        #expect(ComposeAttachmentUploadState.attachmentsNeedingUpload([uploaded, retrying]).map(\.id) == [second.id])
        #expect(ComposeAttachmentUploadState.uploadedAttachmentIDs(from: [uploaded, retrying]) == ["remote-1"])
    }

    @Test("failed uploads are not retried until the user requests retry")
    func failedUploadsAreNotRetriedUntilUserRequestsRetry() {
        let attachment = PendingAttachment(
            filename: "failed.pdf",
            mimeType: "application/pdf",
            data: Data("failed".utf8)
        )

        let failed = ComposeAttachmentUploadState.markFailed(attachment, message: "timeout")
        let retrying = ComposeAttachmentUploadState.clearFailure(failed)

        #expect(ComposeAttachmentUploadState.attachmentsNeedingUpload([failed]).isEmpty)
        #expect(ComposeAttachmentUploadState.attachmentsNeedingUpload([retrying]).map(\.id) == [attachment.id])
        #expect(ComposeAttachmentUploadState
            .unresolvedFailureMessage(for: [failed]) == "Retry or remove failed attachments before saving or sending.")
        #expect(ComposeAttachmentUploadState.unresolvedFailureMessage(for: [retrying]) == nil)
    }

    @Test("autosave does not upload attachment bytes")
    func autosaveDoesNotUploadAttachmentBytes() {
        #expect(ComposeAttachmentUploadState.shouldUploadAttachments(for: .send))
        #expect(ComposeAttachmentUploadState.shouldUploadAttachments(for: .saveDraft))
        #expect(!ComposeAttachmentUploadState.shouldUploadAttachments(for: .autoSaveDraft))
    }

    @Test("inline attachment IDs survive regular attachment upload reconciliation")
    func inlineAttachmentIDsSurviveRegularUploads() {
        #expect(ComposeAttachmentUploadState.mergedAttachmentIDs(
            inline: ["inline-1", "shared"],
            regular: ["regular-1", "shared"]
        ) == ["inline-1", "shared", "regular-1"])
    }

    @Test("staged inline attachment IDs stay scoped to their mailbox source")
    func stagedInlineAttachmentIDsStayScopedToSource() {
        let sourceA = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let sourceB = MailSourceID(accountID: "account-b", mailboxID: "mailbox-b")
        let staged = [
            "cid-a": ComposeStagedInlineAttachment(attachmentID: "attachment-a", sourceID: sourceA),
            "cid-b": ComposeStagedInlineAttachment(attachmentID: "attachment-b", sourceID: sourceB),
        ]

        #expect(ComposeAttachmentUploadState.inlineAttachmentIDs(from: staged, for: sourceA) == ["attachment-a"])
        #expect(!ComposeAttachmentUploadState.shouldStageInlineAttachment(staged["cid-a"], for: sourceA))
        #expect(ComposeAttachmentUploadState.shouldStageInlineAttachment(staged["cid-a"], for: sourceB))
    }

    @Test("draft is saved again only when attachment reconciliation changed IDs")
    func draftResaveRequiresChangedAttachmentIDs() {
        #expect(!ComposeAttachmentUploadState.requiresDraftResave(
            savedAttachmentIDs: ["inline-1"],
            reconciledAttachmentIDs: ["inline-1"]
        ))
        #expect(ComposeAttachmentUploadState.requiresDraftResave(
            savedAttachmentIDs: ["inline-1"],
            reconciledAttachmentIDs: ["inline-1", "regular-1"]
        ))
    }
}
