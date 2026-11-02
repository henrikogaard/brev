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
}

enum ComposeDraftRestoration {
    static func resolve(
        header: MessageHeader,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws -> ComposeRestoredDraft {
        let staged: Draft?
        if let sourceID {
            staged = try await backend.draft(for: header.id, sourceID: sourceID)
        } else {
            staged = try await backend.draft(for: header.id)
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
            remoteID: header.id,
            threadID: header.threadID,
            inReplyToMessageID: header.inReplyTo,
            to: header.to,
            cc: header.cc,
            bcc: header.bcc,
            subject: header.subject,
            htmlBody: body?.html ?? ComposeHTMLBodyPolicy.html(fromEditorText: body?.plainText ?? "")
        ))
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
        if attachments.contains(where: { $0.isInline || $0.contentID != nil })
            || draft.htmlBody.range(of: "cid:", options: .caseInsensitive) != nil {
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
