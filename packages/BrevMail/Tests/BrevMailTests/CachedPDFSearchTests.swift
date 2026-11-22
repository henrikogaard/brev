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

struct CachedPDFSearchTests {
    @Test("PDF results require cached MIME or filename evidence, keep header predicates, and deduplicate")
    func metadata() {
        let folder = Folder(id: "in", name: "Inbox", role: .inbox)
        func message(_ id: String, name: String, mime: String, inline: Bool = false,
                     read: Bool = false) -> CachedAttachmentMessage {
            let header = MessageHeader(id: id, threadID: id, folderID: folder.id, from: Correspondent(email: "ada@example.org"),
                                       to: [], subject: "receipt.pdf", snippet: "", date: .distantPast, isRead: read)
            let attachment = Attachment(id: id, name: name, mimeType: mime, sizeBytes: 1, isInline: inline)
            return CachedAttachmentMessage(
                folder: folder,
                header: header,
                body: MessageBody(messageID: id, attachments: [attachment])
            )
        }
        let mime = message("mime", name: "blob", mime: "application/pdf")
        let rows = [mime, mime, message("extension", name: "RECEIPT.PDF", mime: "application/octet-stream"),
                    message("archive", name: "receipt.pdf.zip", mime: "application/zip"),
                    message("read", name: "read.pdf", mime: "application/pdf", read: true),
                    message("inline", name: "inline.pdf", mime: "application/pdf", inline: true)]
        let plan = NaturalLanguageSearchPlanner.plan(for: "receipt pdf unread", execution: .cacheOnly)
        #expect(CachedPDFSearch.matches(rows, query: plan.query).map(\.id) == ["mime", "extension"])
    }

    @Test("Mock PDF results change when the file-type chip is removed")
    func mockPDFChipRemoval() async throws {
        let backend = MockBackend()
        let source = try await backend.sourceID(for: backend.currentMailbox())
        for name in ["report.PDF", "report.txt"] {
            var draft = Draft(id: name, subject: "quarterly receipt")
            let attachment = try await backend.uploadAttachment(draftID: name, data: Data([1]), filename: name,
                                                                mimeType: "application/octet-stream", sourceID: source)
            draft.attachmentIDs = [attachment]
            _ = try await backend.save(draft: draft, sourceID: source)
        }
        let folders = try await backend.folders(in: source)
        let plan = NaturalLanguageSearchPlanner.plan(for: "quarterly receipt pdf", execution: .cacheOnly)
        let matches = try await MailSearchExecution.run(
            backend: backend,
            query: plan.query,
            sourceID: source,
            cachedPDFFolders: folders
        ) { _ in }
        #expect(matches.map(\.id) == ["draft-report.PDF"])
        let chip = try #require(plan.chips.first { $0.kind == .cachedPDF })
        let removed = NaturalLanguageSearchChipEditing.removing(chip, from: plan.originalText)
        let query = NaturalLanguageSearchPlanner.plan(for: removed, execution: .cacheOnly).query
        let all = try await backend.search(query, sourceID: source)
        #expect(Set(all.map(\.id)) == ["draft-report.PDF", "draft-report.txt"])
        var server = plan.query
        server.execution = .serverOnly
        await #expect(throws: CachedPDFSearch.SearchError.self) {
            try await CachedPDFSearch.headers(backend: backend, query: server, folders: folders, sourceID: source)
        }
    }
}
