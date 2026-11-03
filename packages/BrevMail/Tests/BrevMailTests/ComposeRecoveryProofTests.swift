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

@Suite("Compose recovery proof")
struct ComposeRecoveryProofTests {
    @Test("missing canonical drafts, identity mismatches and stale snapshots never fetch provider bodies", arguments: 0 ..< 5)
    func mismatches(kind: Int) async throws {
        let original = Draft(id: "local", remoteID: "remote", subject: "Original", htmlBody: "<strong>Body</strong>")
        let snapshot = try #require(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: original))
        var canonical: Draft? = original
        switch kind {
        case 0: canonical = nil
        case 1: canonical = Draft(
                id: "different",
                remoteID: original.remoteID,
                subject: original.subject,
                htmlBody: original.htmlBody
            )
        case 2: canonical?.remoteID = "different"
        case 3: canonical?.subject = "Changed"
        default: canonical?.htmlBody = "Changed body"
        }
        let backend = DraftLookupProbe(canonical: canonical)
        await #expect(throws: (any Error).self) {
            try await ComposeDraftRestoration.resolveRecovery(snapshot: snapshot, backend: backend, sourceID: nil)
        }
        #expect(await backend.lookupIDs == ["remote"])
        #expect(await backend.bodyReadCount == 0)
        #expect(await backend.writeCount == 0)
    }

    @Test("a foreign source is refused before lookup")
    func foreignSource() async throws {
        let original = Draft(id: "local", htmlBody: "Body")
        let snapshot = try #require(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: original))
        let backend = DraftLookupProbe(canonical: original)
        await #expect(throws: (any Error).self) {
            try await ComposeDraftRestoration.resolveRecovery(
                snapshot: snapshot,
                backend: backend,
                sourceID: MailSourceID(accountID: "foreign-account", mailboxID: "foreign-mailbox")
            )
        }
        #expect(await backend.lookupIDs.isEmpty)
        #expect(await backend.bodyReadCount == 0)
    }

    @Test("inline metadata and content IDs are independently refused", arguments: [false, true])
    func inlinePayloads(contentID: Bool) async throws {
        let original = Draft(id: "local", htmlBody: "Body", attachmentIDs: ["part"])
        let payload = MIMEMessageAttachment(
            id: "part",
            filename: "image.png",
            mimeType: "image/png",
            data: Data([1]),
            isInline: !contentID,
            contentID: contentID ? "local-image" : nil
        )
        let backend = DraftLookupProbe(canonical: original, payloads: [payload])
        let snapshot = try #require(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: original))
        await #expect(throws: (any Error).self) {
            try await ComposeDraftRestoration.resolveRecovery(snapshot: snapshot, backend: backend, sourceID: nil)
        }
        #expect(await backend.bodyReadCount == 0)
        #expect(await backend.writeCount == 0)
    }

    @Test("legacy JSON remains a hint and resolves formatted canonical content")
    func legacyJSON() async throws {
        let data = Data(#"{"draftID":"local","remoteID":"remote","to":[],"cc":[],"bcc":[],"subject":"Original","bodyText":"Bold"}"#
            .utf8)
        let snapshot = try JSONDecoder().decode(ComposeDraftRecoverySnapshot.self, from: data)
        let draft = Draft(id: "local", remoteID: "remote", subject: "Original", htmlBody: "<strong>Bold</strong>")
        let backend = DraftLookupProbe(canonical: draft)
        let resolved = try await ComposeDraftRestoration.resolveRecovery(snapshot: snapshot, backend: backend, sourceID: nil)
        #expect(resolved.draft == draft)
        #expect(await backend.bodyReadCount == 0)
    }

    @Test("the server-sourced flag excuses only a missing canonical copy")
    func serverSourcedExcusesOnlyMissingCopy() async throws {
        let draft = Draft(id: "server", remoteID: "message", htmlBody: "Body")
        let missing = DraftLookupProbe(canonical: nil)
        let resolved = try await ComposeDraftRestoration.resolveExisting(
            draft: draft, isServerSourced: true, backend: missing, sourceID: nil
        )
        #expect(resolved.draft == draft)
        await #expect(throws: (any Error).self) {
            _ = try await ComposeDraftRestoration.resolveExisting(
                draft: draft, isServerSourced: false, backend: missing, sourceID: nil
            )
        }
        let different = DraftLookupProbe(canonical: Draft(id: "server", remoteID: "message", htmlBody: "Newer"))
        await #expect(throws: (any Error).self) {
            _ = try await ComposeDraftRestoration.resolveExisting(
                draft: draft, isServerSourced: true, backend: different, sourceID: nil
            )
        }
    }

    @Test("reply and forward drafts without a quote boundary still prepare", arguments: [false, true])
    @MainActor
    func unprovenQuoteBoundary(forward: Bool) async throws {
        let draft = Draft(
            id: "quote",
            inReplyToMessageID: forward ? nil : "reply",
            forwardedMessageID: forward ? "forward" : nil,
            htmlBody: "<strong>Body</strong>"
        )
        let body = try await ComposeDraftBodyRestoration.prepare(draft: draft, format: .richTextHTML)
        #expect(body.originalHTML == draft.htmlBody)
    }
}

actor DraftLookupProbe: MailBackend, LocalDraftAttachmentProviding {
    nonisolated let account = MockBackend().account
    nonisolated let capabilities = MockBackend().capabilities
    private let canonical: Draft?
    private let payloads: [MIMEMessageAttachment]
    private let holdsLookup: Bool
    private var lookupStarted: CheckedContinuation<Void, Never>?
    private var lookupRelease: CheckedContinuation<Void, Never>?
    private(set) var lookupIDs: [String] = []
    private(set) var bodyReadCount = 0
    private(set) var writeCount = 0

    init(canonical: Draft?, payloads: [MIMEMessageAttachment] = [], holdsLookup: Bool = false) {
        self.canonical = canonical
        self.payloads = payloads
        self.holdsLookup = holdsLookup
    }

    func draft(for messageID: String) async throws -> Draft? {
        lookupIDs.append(messageID)
        lookupStarted?.resume()
        lookupStarted = nil
        if holdsLookup { await withCheckedContinuation { lookupRelease = $0 } }
        return canonical
    }

    func waitForLookup() async {
        if lookupIDs.isEmpty { await withCheckedContinuation { lookupStarted = $0 } }
    }

    func releaseLookup() {
        lookupRelease?.resume()
        lookupRelease = nil
    }

    func localDraftAttachments(for _: Draft) async throws -> [MIMEMessageAttachment] { payloads }
    func localDraftAttachments(for _: Draft, sourceID _: MailSourceID) async throws -> [MIMEMessageAttachment] { payloads }
    func body(for messageID: String) async throws -> MessageBody {
        bodyReadCount += 1
        return MessageBody(messageID: messageID, html: canonical?.htmlBody)
    }

    func save(draft: Draft) async throws -> Draft { writeCount += 1; return draft }
    func send(draft _: Draft) async throws -> SendResult { writeCount += 1; return SendResult(sentMessageID: "sent") }
    func discard(draftID _: String) async throws { writeCount += 1 }
    func connect() async throws {}
    func disconnect() async {}
    func folders() async throws -> [Folder] { [] }
    func refresh(folder _: Folder) async throws {}
    func messages(in _: Folder, pageToken _: String?) async throws -> (headers: [MessageHeader], nextPageToken: String?) { (
        [],
        nil
    ) }
    func setRead(_: Bool, for _: [String]) async throws {}
    func setFlagged(_: Bool, for _: [String]) async throws {}
    func move(messageIDs _: [String], to _: Folder) async throws {}
    func delete(messageIDs _: [String]) async throws {}
    func search(_: SearchQuery) async throws -> [MessageHeader] { [] }
    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent { throw MailBackendError
        .notFound(id: attachmentID)
    }

    func replyToCalendarInvite(messageID _: String, response _: AttendeeState) async throws {}
    nonisolated func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }
}
