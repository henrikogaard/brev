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

struct ComposeStagedInlineAttachment: Equatable, Sendable {
    let attachmentID: String
    let sourceID: MailSourceID
}

enum ComposeAttachmentUploadState {
    static func shouldUploadAttachments(for operationKind: ComposeOperationKind) -> Bool {
        switch operationKind {
        case .send, .saveDraft:
            return true
        case .autoSaveDraft:
            return false
        }
    }

    static func markUploaded(
        _ attachment: PendingAttachment,
        remoteID: String
    ) -> PendingAttachment {
        PendingAttachment(
            id: attachment.id,
            filename: attachment.filename,
            mimeType: attachment.mimeType,
            data: attachment.data,
            uploadErrorMessage: nil,
            uploadedAttachmentID: remoteID
        )
    }

    static func markFailed(
        _ attachment: PendingAttachment,
        message: String
    ) -> PendingAttachment {
        PendingAttachment(
            id: attachment.id,
            filename: attachment.filename,
            mimeType: attachment.mimeType,
            data: attachment.data,
            uploadErrorMessage: message,
            uploadedAttachmentID: attachment.uploadedAttachmentID
        )
    }

    static func clearFailure(_ attachment: PendingAttachment) -> PendingAttachment {
        PendingAttachment(
            id: attachment.id,
            filename: attachment.filename,
            mimeType: attachment.mimeType,
            data: attachment.data,
            uploadErrorMessage: nil,
            uploadedAttachmentID: attachment.uploadedAttachmentID
        )
    }

    static func attachmentsNeedingUpload(_ attachments: [PendingAttachment]) -> [PendingAttachment] {
        attachments.filter {
            $0.uploadedAttachmentID == nil && $0.uploadErrorMessage == nil
        }
    }

    static func uploadedAttachmentIDs(from attachments: [PendingAttachment]) -> [String] {
        attachments.compactMap(\.uploadedAttachmentID)
    }

    /// Keeps staged CID parts alongside ordinary uploaded files without
    /// duplicating an ID if a backend happens to reuse one.
    static func mergedAttachmentIDs(inline: [String], regular: [String]) -> [String] {
        var seen = Set<String>()
        return (inline + regular).filter { seen.insert($0).inserted }
    }

    static func inlineAttachmentIDs(
        from staged: [String: ComposeStagedInlineAttachment],
        for sourceID: MailSourceID
    ) -> [String] {
        staged
            .filter { $0.value.sourceID == sourceID }
            .sorted { $0.key < $1.key }
            .map(\.value.attachmentID)
    }

    static func shouldStageInlineAttachment(
        _ staged: ComposeStagedInlineAttachment?,
        for sourceID: MailSourceID
    ) -> Bool {
        staged?.sourceID != sourceID
    }

    static func requiresDraftResave(
        savedAttachmentIDs: [String],
        reconciledAttachmentIDs: [String]
    ) -> Bool {
        savedAttachmentIDs != reconciledAttachmentIDs
    }

    static func unresolvedFailureMessage(for attachments: [PendingAttachment]) -> String? {
        attachments.contains { $0.uploadErrorMessage != nil }
            ? "Retry or remove failed attachments before saving or sending."
            : nil
    }

    static func statusText(for attachment: PendingAttachment) -> String? {
        guard let uploadErrorMessage = attachment.uploadErrorMessage else { return nil }
        return "Upload failed: \(uploadErrorMessage)"
    }

    static func retryActionTitle(for attachment: PendingAttachment) -> String? {
        attachment.uploadErrorMessage == nil ? nil : "Retry on Send"
    }
}
