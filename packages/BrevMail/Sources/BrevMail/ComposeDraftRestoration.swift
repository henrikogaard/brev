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

struct ComposeRestoredDraft: Sendable {
    let draft: Draft
    var attachments: [MIMEMessageAttachment] = []
    /// True when the body came from the server because no local copy exists.
    var isServerSourced = false
}

enum ComposeDraftRestoration {
    static func resolveExisting(
        draft: Draft,
        isServerSourced: Bool = false,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws -> ComposeRestoredDraft {
        try Task.checkCancellation()
        guard sourceID == nil || sourceID?.accountID == backend.account.id else {
            throw MailBackendError.backendSpecific(message: recoveryUnavailableMessage)
        }
        let canonical: Draft?
        if let sourceID {
            canonical = try await backend.draft(for: draft.remoteID ?? draft.id, sourceID: sourceID)
        } else {
            canonical = try await backend.draft(for: draft.remoteID ?? draft.id)
        }
        // ADR-0093: a server-sourced open excuses a missing copy, never a different one.
        guard canonical == draft || (isServerSourced && canonical == nil) else {
            throw MailBackendError.backendSpecific(message: recoveryUnavailableMessage)
        }
        try Task.checkCancellation()
        let attachments = try await localAttachments(for: draft, backend: backend, sourceID: sourceID)
        try Task.checkCancellation()
        if let message = validationError(draft: draft, attachments: attachments) {
            throw MailBackendError.backendSpecific(message: message)
        }
        return ComposeRestoredDraft(draft: draft, attachments: attachments)
    }

    static func resolveRecovery(
        snapshot: ComposeDraftRecoverySnapshot,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws -> ComposeRestoredDraft {
        try Task.checkCancellation()
        guard sourceID == nil || sourceID?.accountID == backend.account.id else {
            throw MailBackendError.backendSpecific(message: recoveryUnavailableMessage)
        }
        let staged: Draft?
        if let sourceID {
            staged = try await backend.draft(for: snapshot.remoteID ?? snapshot.draftID, sourceID: sourceID)
        } else {
            staged = try await backend.draft(for: snapshot.remoteID ?? snapshot.draftID)
        }
        guard let draft = staged,
              draft.id == snapshot.draftID,
              draft.remoteID == snapshot.remoteID,
              ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: draft) == snapshot else {
            throw MailBackendError.backendSpecific(message: recoveryUnavailableMessage)
        }
        try Task.checkCancellation()
        let attachments = try await localAttachments(for: draft, backend: backend, sourceID: sourceID)
        try Task.checkCancellation()
        if let message = validationError(draft: draft, attachments: attachments) {
            throw MailBackendError.backendSpecific(message: message)
        }
        return ComposeRestoredDraft(draft: draft, attachments: attachments)
    }

    private static func localAttachments(
        for draft: Draft,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws -> [MIMEMessageAttachment] {
        guard !draft.attachmentIDs.isEmpty else { return [] }
        guard let service = backend.extensionService(LocalDraftAttachmentProviding.self) else {
            throw MailBackendError.backendSpecific(message: unavailableMessage)
        }
        if let sourceID {
            return try await service.localDraftAttachments(for: draft, sourceID: sourceID)
        }
        return try await service.localDraftAttachments(for: draft)
    }

    static var recoveryUnavailableMessage: String {
        String(
            localized: "This draft cannot be restored safely from local storage. Close this window to leave the original unchanged.",
            bundle: .module
        )
    }

    static func resolve(
        header: MessageHeader,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws -> ComposeRestoredDraft {
        var staged: Draft?
        if let sourceID {
            staged = try await backend.draft(for: header.id, sourceID: sourceID)
        } else {
            staged = try await backend.draft(for: header.id)
        }
        var remoteID = header.id
        if staged == nil, let resolver = backend.extensionService(DraftIdentityResolving.self) {
            guard let draftID = try await resolver.remoteDraftID(forMessageID: header.id, sourceID: sourceID) else {
                throw MailBackendError.backendSpecific(message: recoveryUnavailableMessage)
            }
            remoteID = draftID
            if let sourceID {
                staged = try await backend.draft(for: draftID, sourceID: sourceID)
            } else {
                staged = try await backend.draft(for: draftID)
            }
        }
        if let staged {
            var attachments: [MIMEMessageAttachment] = []
            if !staged.attachmentIDs.isEmpty {
                guard let service = backend.extensionService(LocalDraftAttachmentProviding.self) else {
                    throw MailBackendError.backendSpecific(message: unavailableMessage)
                }
                do {
                    if let sourceID {
                        attachments = try await service.localDraftAttachments(for: staged, sourceID: sourceID)
                    } else {
                        attachments = try await service.localDraftAttachments(for: staged)
                    }
                } catch {
                    throw MailBackendError.backendSpecific(message: unavailableMessage)
                }
            } else if header.hasAttachments {
                throw MailBackendError.backendSpecific(message: unavailableMessage)
            }
            if let message = validationError(draft: staged, attachments: attachments) {
                throw MailBackendError.backendSpecific(message: message)
            }
            return ComposeRestoredDraft(draft: staged, attachments: attachments)
        }
        guard !header.hasAttachments else { throw MailBackendError.backendSpecific(message: unavailableMessage) }
        let body: MessageBody?
        if let sourceID {
            body = try await backend.body(for: header.id, sourceID: sourceID)
        } else {
            body = try await backend.body(for: header.id)
        }
        guard body?.attachments.isEmpty != false else {
            throw MailBackendError.backendSpecific(message: unavailableMessage)
        }
        let restored = ComposeRestoredDraft(draft: Draft(
            id: UUID().uuidString,
            remoteID: remoteID,
            threadID: header.threadID,
            inReplyToMessageID: header.inReplyTo,
            to: header.to,
            cc: header.cc,
            bcc: header.bcc,
            subject: header.subject,
            htmlBody: body?.html ?? ComposeHTMLBodyPolicy.html(fromEditorText: body?.plainText ?? "")
        ), isServerSourced: true)
        if let message = validationError(draft: restored.draft, attachments: []) {
            throw MailBackendError.backendSpecific(message: message)
        }
        return restored
    }

    static func pendingAttachments(from attachments: [MIMEMessageAttachment]) -> [PendingAttachment] {
        attachments.map {
            PendingAttachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data, uploadedAttachmentID: $0.id)
        }
    }

    static func validationError(draft: Draft, attachments: [MIMEMessageAttachment]) -> String? {
        guard attachments.map(\.id) == draft.attachmentIDs,
              Set(draft.attachmentIDs).count == draft.attachmentIDs.count else { return unavailableMessage }
        // The compose sanitizer retains only CID-backed image tags, not literal CID text.
        if attachments.contains(where: { $0.isInline || $0.contentID != nil })
            || ComposeHTMLBodyPolicy.richHTML(fromEditorHTML: draft.htmlBody).contains("<img src=") {
            return String(
                localized: "This draft contains inline images that cannot be restored safely yet. The draft was left unchanged.",
                bundle: .module
            )
        }
        var remaining = ComposeAttachmentImport.maxAttachmentByteCount
        for attachment in attachments {
            guard attachment.data.count <= remaining else {
                return ComposeAttachmentImport.attachmentBudgetExceededMessage(filename: attachment.filename)
            }
            remaining -= attachment.data.count
        }
        return nil
    }

    static var unavailableMessage: String {
        String(localized: "Attachments for this draft are not available locally. The draft was left unchanged.", bundle: .module)
    }

    static func allowsSender(_ candidate: ComposeSenderOption, current: ComposeSenderOption, isRestored: Bool) -> Bool {
        !isRestored || (candidate.accountID == current.accountID && candidate.sourceID == current.sourceID)
    }
}
