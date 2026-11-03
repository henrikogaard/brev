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

@Suite("ComposeDraftRestoration")
struct ComposeDraftRestorationTests {
    @Test("literal CID text remains editable without attachments", arguments: [
        "<p>Please explain cid:photo in this text</p>",
        "<p>Please explain CID:photo in this text</p>",
        "<p>Example: src=\"cid:photo\"</p>",
        "<p>&lt;img src=\"cid:photo\"&gt;</p>",
        "<p title=\"cid:photo\">Ordinary text</p>",
        "<img src=\"https://example.test/photo.png\" alt=\"cid:photo\">"
    ])
    func literalCIDTextRemainsEditable(html: String) async throws {
        let backend = MockBackend()
        let saved = try await backend.save(draft: Draft(id: "literal-cid", htmlBody: html))
        #expect(ComposeDraftRestoration.validationError(draft: saved, attachments: []) == nil)
        let folder = try #require(await backend.folders().first { $0.role == .drafts })
        let header = try #require(await backend.messages(in: folder, pageToken: nil).0.first { $0.id == saved.remoteID })
        let restored = try await ComposeDraftRestoration.resolve(header: header, backend: backend, sourceID: nil)
        #expect(restored.draft == saved)
        #expect(restored.attachments.isEmpty)
    }

    @Test("real quoted and unquoted CID images remain blocked without payload metadata", arguments: [
        "<img src=\"cid:photo\">",
        "<img src='cid:photo'>",
        "<img src=cid:photo>",
        "<IMG SRC = CID:photo>",
        "<img alt='Photo' src = ' cid:photo '>",
        "<img src=cid:photo />"
    ])
    func cidImageReferencesFailClosed(html: String) {
        #expect(ComposeDraftRestoration.validationError(draft: Draft(id: "local", htmlBody: html), attachments: []) != nil)
    }

    @Test("inline flags and content IDs independently block restoration without body references")
    func inlineMetadataRemainsBlocked() {
        let draft = Draft(id: "local", htmlBody: "<p>Ordinary text</p>", attachmentIDs: ["part"])
        for payload in [
            MIMEMessageAttachment(id: "part", filename: "photo.png", mimeType: "image/png", data: Data([1]), isInline: true),
            MIMEMessageAttachment(id: "part", filename: "photo.png", mimeType: "image/png", data: Data([1]), contentID: "photo")
        ] {
            #expect(ComposeDraftRestoration.validationError(draft: draft, attachments: [payload]) != nil)
        }
    }

    @Test("navigation hands off payloads and clears them when starting another draft")
    @MainActor
    func navigationPayloadLifecycle() {
        let navigation = MailNavigationState()
        let payload = MIMEMessageAttachment(id: "R", filename: "old.txt", mimeType: "text/plain", data: Data([1]))
        let draft = Draft(id: "local", attachmentIDs: [payload.id])
        navigation.presentDraft(draft, attachments: [payload])
        #expect(navigation.composeDraft == draft)
        #expect(navigation.composeDraftAttachments == [payload])
        navigation.composeDraft = nil
        #expect(navigation.composeDraftAttachments.isEmpty)
    }

    @Test("inline draft restoration fails before editing and keeps the saved CID body and IDs intact")
    func inlineRoundTripFailsClosed() async throws {
        let backend = MockBackend()
        var draft = Draft(id: "inline", htmlBody: "<img src=\"cid:photo\">")
        draft.attachmentIDs = try await [backend.uploadAttachment(
            draftID: draft.id,
            data: Data([1]),
            filename: "photo.png",
            mimeType: "image/png"
        )]
        draft = try await backend.save(draft: draft)
        let folder = try #require(await backend.folders().first { $0.role == .drafts })
        let header = try #require(await backend.messages(in: folder, pageToken: nil).0.first { $0.id == draft.remoteID })
        await #expect(throws: (any Error).self) {
            try await ComposeDraftRestoration.resolve(header: header, backend: backend, sourceID: nil)
        }
        #expect(try await backend.draft(for: #require(draft.remoteID)) == draft)
        #expect(try await backend.body(for: header.id).html == draft.htmlBody)
    }

    @Test("private SwiftUI wiring uses one authoritative ID set and validated payloads")
    func restorationWiring() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/BrevMail")
        let compose = try String(contentsOf: source.appendingPathComponent("ComposeView.swift"), encoding: .utf8)
        let root = try String(contentsOf: source.appendingPathComponent("BrevMailRootView.swift"), encoding: .utf8)
        #expect(root.contains("ComposeDraftRestoration.resolve("))
        #expect(root.contains("existingDraftAttachments: navigation.composeDraftAttachments"))
        #expect(compose.contains("ComposeDraftRestoration.pendingAttachments(from: existingDraftAttachments)"))
        #expect(compose.contains("let reconciledAttachmentIDs = currentAttachmentIDs"))
        #expect(compose.contains("attachmentIDs: currentAttachmentIDs"))
        #expect(!compose.contains("for id in restoredDraft?.attachmentIDs"))
        #expect(compose.contains("isBlocked: isWorkBlocked || restorationBlocksWork"))
        #expect(compose.contains("pendingAttachments.contains { restoredDraft == nil || $0.uploadedAttachmentID == nil }"))
        #expect(compose.contains("existingByteCount: pendingAttachments.reduce(0) { $0 + $1.data.count }"))
    }

    @Test("server-only header or body attachments leave the draft unopened")
    func serverOnlyAttachments() async throws {
        let backend = MockBackend()
        let folder = try #require(await backend.folders().first { $0.role == .inbox })
        let header = try #require(await backend.messages(in: folder, pageToken: nil).0.first { $0.id == "m1" })
        let body = try await backend.body(for: header.id)
        #expect(!body.attachments.isEmpty)
        #expect(header.hasAttachments)
        await #expect(throws: (any Error).self) {
            try await ComposeDraftRestoration.resolve(header: header, backend: backend, sourceID: nil)
        }
        let missingFlag = MessageHeader(
            id: header.id,
            threadID: header.threadID,
            folderID: header.folderID,
            from: header.from,
            subject: header.subject,
            snippet: header.snippet,
            date: header.date
        )
        await #expect(throws: (any Error).self) {
            try await ComposeDraftRestoration.resolve(header: missingFlag, backend: backend, sourceID: nil)
        }
        #expect(try await backend.body(for: header.id) == body)
    }

    @Test("reopened source binding permits aliases, rejects other accounts/mailboxes; fresh compose stays unrestricted")
    func sourceBinding() {
        let source = MailSourceID(accountID: "account", mailboxID: "a")
        let current = ComposeSenderOption(
            sourceID: source,
            accountID: "account",
            displayName: nil,
            email: "me@example.test",
            subtitle: ""
        )
        let alias = ComposeSenderOption(
            sourceID: source,
            accountID: "account",
            displayName: nil,
            email: "alias@example.test",
            subtitle: ""
        )
        let other = ComposeSenderOption(
            sourceID: MailSourceID(accountID: "account", mailboxID: "b"),
            accountID: "account",
            displayName: nil,
            email: "me@example.test",
            subtitle: ""
        )
        let foreign = ComposeSenderOption(
            sourceID: source,
            accountID: "foreign",
            displayName: nil,
            email: "me@example.test",
            subtitle: ""
        )
        #expect(ComposeDraftRestoration.allowsSender(alias, current: current, isRestored: true))
        #expect(!ComposeDraftRestoration.allowsSender(other, current: current, isRestored: true))
        #expect(!ComposeDraftRestoration.allowsSender(foreign, current: current, isRestored: true))
        #expect(ComposeDraftRestoration.allowsSender(other, current: current, isRestored: false))
    }

    @Test("old plus new uploads, save and autosave removal use owned real bytes")
    func editRoundTrip() async throws {
        let backend = MockBackend()
        var draft = Draft(id: "edits", subject: "edits", htmlBody: "body")
        let oldID = try await backend.uploadAttachment(
            draftID: draft.id,
            data: Data([1]),
            filename: "old.txt",
            mimeType: "text/plain"
        )
        draft.attachmentIDs = [oldID]
        draft = try await backend.save(draft: draft)
        let service = try #require(backend.extensionService(LocalDraftAttachmentProviding.self))
        var pending = try await ComposeDraftRestoration.pendingAttachments(from: service.localDraftAttachments(for: draft))
        let row = try ComposeAttachmentRowPresentation.presentation(for: #require(pending.first))
        #expect(row.filename == "old.txt")
        #expect(row.statusText == "Ready to send")
        #expect(row.removeAccessibilityLabel.contains("old.txt"))
        #expect(!ComposeSendDraftPersistencePolicy
            .shouldPersistDraftBeforeSend(hasPendingAttachments: pending.contains { $0.uploadedAttachmentID == nil }))
        pending.append(PendingAttachment(filename: "new.txt", mimeType: "text/plain", data: Data([2])))
        #expect(ComposeSendDraftPersistencePolicy
            .shouldPersistDraftBeforeSend(hasPendingAttachments: pending.contains { $0.uploadedAttachmentID == nil }))
        let uploads = ComposeAttachmentUploadState.attachmentsNeedingUpload(pending)
        #expect(uploads.map(\.filename) == ["new.txt"])
        let upload = try #require(uploads.first)
        let newID = try await backend.uploadAttachment(
            draftID: #require(draft.remoteID),
            data: upload.data,
            filename: upload.filename,
            mimeType: upload.mimeType
        )
        pending = pending.map { $0.id == upload.id ? PendingAttachment(
            id: $0.id,
            filename: $0.filename,
            mimeType: $0.mimeType,
            data: $0.data,
            uploadedAttachmentID: newID
        ) : $0 }
        draft.attachmentIDs = ComposeAttachmentUploadState.mergedAttachmentIDs(
            inline: [],
            regular: ComposeAttachmentUploadState.uploadedAttachmentIDs(from: pending)
        )
        draft = try await backend.save(draft: draft)
        #expect(try await service.localDraftAttachments(for: draft).map(\.id) == [oldID, newID])
        pending.removeAll { $0.uploadedAttachmentID == oldID }
        for _ in 0 ..< 2 {
            draft.attachmentIDs = ComposeAttachmentUploadState.uploadedAttachmentIDs(from: pending)
            draft = try await backend.save(draft: draft)
            #expect(try await service.localDraftAttachments(for: draft).map(\.id) == [newID])
        }
        pending.removeAll()
        draft.attachmentIDs = ComposeAttachmentUploadState.uploadedAttachmentIDs(from: pending)
        draft = try await backend.save(draft: draft)
        #expect(try await service.localDraftAttachments(for: draft).isEmpty)
    }

    @Test("later file import includes restored bytes in the aggregate budget")
    func laterImportBudget() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await ComposeAttachmentImport.importFiles(
            from: [url],
            existingByteCount: ComposeAttachmentImport.maxAttachmentByteCount
        )
        #expect(result.attachments.isEmpty)
        #expect(result.errorMessage != nil)
    }

    @Test("mock save reopens the canonical draft and real attachment rows")
    func mockRoundTrip() async throws {
        let backend = MockBackend()
        let bytes = Data("retained bytes".utf8)
        var draft = Draft(id: "local", subject: "roundtrip", htmlBody: "body")
        let id = try await backend.uploadAttachment(draftID: draft.id, data: bytes, filename: "old.txt", mimeType: "text/plain")
        draft.attachmentIDs = [id]
        let saved = try await backend.save(draft: draft)
        let folder = try #require(await backend.folders().first { $0.role == .drafts })
        let header = try #require(await backend.messages(in: folder, pageToken: nil).0.first { $0.id == saved.remoteID })
        let restored = try await ComposeDraftRestoration.resolve(header: header, backend: backend, sourceID: nil)
        #expect(restored.draft.id == draft.id)
        #expect(restored.draft.attachmentIDs == [id])
        let rows = ComposeDraftRestoration.pendingAttachments(from: restored.attachments)
        #expect(rows.map(\.data) == [bytes])
        #expect(rows.map(\.filename) == ["old.txt"])
        #expect(ComposeAttachmentUploadState.attachmentsNeedingUpload(rows).isEmpty)
        var resaved = restored.draft
        resaved.attachmentIDs = ComposeAttachmentUploadState.uploadedAttachmentIDs(from: rows)
        let result = try await backend.save(draft: resaved)
        let body = try await backend.body(for: #require(result.remoteID))
        #expect(body.attachments.map(\.id) == [id])
    }

    @Test("restored rows retain old plus new uploads exactly once and removal stays removed")
    func reconciliation() {
        let payload = MIMEMessageAttachment(id: "R", filename: "old.txt", mimeType: "text/plain", data: Data([1, 2]))
        let old = ComposeDraftRestoration.pendingAttachments(from: [payload])
        let new = PendingAttachment(filename: "new.txt", mimeType: "text/plain", data: Data([3]), uploadedAttachmentID: "N")
        let ids = ComposeAttachmentUploadState.mergedAttachmentIDs(
            inline: [],
            regular: ComposeAttachmentUploadState.uploadedAttachmentIDs(from: old + [new])
        )
        #expect(ids == ["R", "N"])
        #expect(ComposeAttachmentUploadState.uploadedAttachmentIDs(from: [new]) == ["N"])
        #expect(ComposeAttachmentUploadState.mergedAttachmentIDs(inline: ["R"], regular: ids) == ["R", "N"])
    }

    @Test("missing and oversized payloads fail closed; real exact-budget payload is allowed")
    func completenessAndBudget() {
        let draft = Draft(id: "local", attachmentIDs: ["R"])
        #expect(ComposeDraftRestoration.validationError(draft: draft, attachments: []) != nil)
        let payload = MIMEMessageAttachment(
            id: "R",
            filename: "full.bin",
            mimeType: "application/octet-stream",
            data: Data(count: ComposeAttachmentImport.maxAttachmentByteCount)
        )
        #expect(ComposeDraftRestoration.validationError(draft: draft, attachments: [payload]) == nil)
        let extra = MIMEMessageAttachment(id: "N", filename: "extra.bin", mimeType: "application/octet-stream", data: Data([1]))
        #expect(ComposeDraftRestoration.validationError(
            draft: Draft(id: "local", attachmentIDs: ["R", "N"]),
            attachments: [payload, extra]
        ) != nil)
    }

    @Test("plain-editor conversion loses CID markup so inline restoration must fail closed")
    func inlineFailsClosed() {
        let html = "<p>Keep this image</p><img src=\"cid:photo\">"
        let text = ComposeHTMLBodyPolicy.editorText(fromStoredHTML: html)
        #expect(!ComposeHTMLBodyPolicy.html(fromEditorText: text).contains("cid:photo"))
        let payload = MIMEMessageAttachment(
            id: "R",
            filename: "photo.png",
            mimeType: "image/png",
            data: Data([1]),
            isInline: true,
            contentID: "photo"
        )
        #expect(ComposeDraftRestoration.validationError(
            draft: Draft(id: "local", htmlBody: html, attachmentIDs: ["R"]),
            attachments: [payload]
        ) != nil)
        #expect(ComposeDraftRestoration.validationError(draft: Draft(id: "local", htmlBody: html), attachments: []) != nil)
    }
}
