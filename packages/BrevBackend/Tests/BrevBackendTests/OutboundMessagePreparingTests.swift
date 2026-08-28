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

@testable import BrevBackend
import Foundation
import Testing

// MARK: - Helpers

/// Records the bytes handed to it and returns a fixed "prepared" payload so the
/// test can prove the send path used the prepared bytes, not the plaintext.
private final class CapturingPreparer: OutboundMessagePreparing, @unchecked Sendable {
    static let preparedMarker = Data("PREPARED-CIPHERTEXT".utf8)
    private let lock = NSLock()
    private(set) var requests: [OutboundMessageSecurityRequest] = []
    private(set) var receivedPlaintext: [Data] = []

    func prepare(mimeData: Data, request: OutboundMessageSecurityRequest) async throws -> Data {
        lock.withLock {
            requests.append(request)
            receivedPlaintext.append(mimeData)
        }
        return Self.preparedMarker
    }
}

private actor DataCapture {
    private(set) var submissionData: [Data] = []
    private(set) var appendData: [Data] = []
    func recordSubmission(_ data: Data) { submissionData.append(data) }
    func recordAppend(_ data: Data) { appendData.append(data) }
}

private enum Fixtures {
    static let account = BrevAccount(
        id: "imap-smtp:person@example.org",
        displayName: "Person",
        emailAddress: "person@example.org"
    )
    static let configuration = IMAPAccountConfiguration(
        accountID: "imap-smtp:person@example.org",
        emailAddress: "person@example.org",
        displayName: "Person",
        incoming: MailServerSettings(
            kind: .imap, host: "imap.example.org", port: 993,
            tlsMode: .implicit, authentication: .password
        ),
        outgoing: MailServerSettings(
            kind: .smtp, host: "smtp.example.org", port: 587,
            tlsMode: .startTLS, authentication: .password
        ),
        credentialID: "imap-smtp:person@example.org"
    )
    static let credential = MailAccountCredential(
        incomingUsername: "person@example.org",
        outgoingUsername: "person@example.org",
        secret: "secret",
        authentication: .password
    )

    static func makeBackend(
        capture: DataCapture,
        preparer: (any OutboundMessagePreparing)?,
        offlineQueue: (any OfflineMutationQueue)? = nil
    ) -> IMAPSMTPBackend {
        IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: { _, _ in [
                IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
                IMAPFolderListing(path: "Sent", displayName: "Sent", delimiter: "/", flags: ["sent"], role: .sent),
            ] },
            sendMessage: { _, _, submission in
                await capture.recordSubmission(submission.messageData)
                return SendResult(sentMessageID: "smtp-accepted")
            },
            appendSentMessage: { _, _, _, messageData, _ in
                await capture.recordAppend(messageData)
                return 1
            },
            offlineMutationQueue: offlineQueue,
            outboundMessagePreparer: preparer
        )
    }
}

// MARK: - Mode mapping

@Suite("OutboundMessageSecurityMode mapping")
struct OutboundMessageSecurityModeMappingTests {
    @Test("compose toggles map to the right mode")
    func togglesMapToMode() {
        #expect(OutboundMessageSecurityMode(signing: false, encrypting: false) == .none)
        #expect(OutboundMessageSecurityMode(signing: true, encrypting: false) == .sign)
        #expect(OutboundMessageSecurityMode(signing: false, encrypting: true) == .encrypt)
        #expect(OutboundMessageSecurityMode(signing: true, encrypting: true) == .signAndEncrypt)
    }
}

// MARK: - Draft Codable back-compat

@Suite("Draft securityMode Codable")
struct DraftSecurityModeCodableTests {
    @Test("a draft persisted before securityMode existed decodes as .none")
    func decodesLegacyDraft() throws {
        let legacy = #"{"id":"d1","to":[],"cc":[],"bcc":[],"subject":"hi","htmlBody":"<p>x</p>","attachmentIDs":[]}"#
        let draft = try JSONDecoder().decode(Draft.self, from: Data(legacy.utf8))
        #expect(draft.securityMode == .none)
        #expect(draft.readReceiptRequest == nil)
        #expect(draft.subject == "hi")
    }

    @Test("securityMode round-trips through Codable")
    func roundTrips() throws {
        let draft = Draft(id: "d2", securityMode: .signAndEncrypt)
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(Draft.self, from: data)
        #expect(decoded.securityMode == .signAndEncrypt)
    }

    @Test("read receipt request round-trips through Codable")
    func readReceiptRequestRoundTrips() throws {
        let draft = Draft(
            id: "d3",
            readReceiptRequest: ReadReceiptRequest(notificationTo: "alice@example.org")
        )
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(Draft.self, from: data)
        #expect(decoded.readReceiptRequest?.notificationTo == "alice@example.org")
    }
}

// MARK: - Send-path seam

@Suite("Outbound preparation on send")
struct OutboundPreparationSendTests {
    private func draft(mode: OutboundMessageSecurityMode) -> Draft {
        Draft(
            id: "draft-sec",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Secure subject",
            htmlBody: "<p>Plaintext body</p>",
            securityMode: mode
        )
    }

    @Test("a signed send uses the prepared bytes for BOTH SMTP and the Sent copy")
    func preparedBytesUsedForSmtpAndSentCopy() async throws {
        let capture = DataCapture()
        let preparer = CapturingPreparer()
        let backend = Fixtures.makeBackend(capture: capture, preparer: preparer)
        try await backend.connect()

        _ = try await backend.send(draft: draft(mode: .sign))

        // Both transports received the prepared ciphertext, not the plaintext.
        #expect(await capture.submissionData == [CapturingPreparer.preparedMarker])
        #expect(await capture.appendData == [CapturingPreparer.preparedMarker])
        // The preparer saw the plaintext MIME (which still contains the subject).
        #expect(preparer.requests.count == 1)
        #expect(preparer.requests.first?.mode == .sign)
        let plaintext = try #require(preparer.receivedPlaintext.first)
        #expect(String(decoding: plaintext, as: UTF8.self).contains("Secure subject"))
    }

    @Test("encryption requested with no engine fails closed — never sends plaintext")
    func failsClosedWithoutEngine() async throws {
        let capture = DataCapture()
        let backend = Fixtures.makeBackend(capture: capture, preparer: nil)
        try await backend.connect()

        await #expect(throws: OutboundCryptoEngineUnavailableError.self) {
            _ = try await backend.send(draft: draft(mode: .encrypt))
        }
        // Nothing was transmitted or filed.
        #expect(await capture.submissionData.isEmpty)
        #expect(await capture.appendData.isEmpty)
    }

    @Test("a security failure is surfaced, never silently queued for offline retry")
    func securityFailureNotQueued() async throws {
        let defaults = try #require(UserDefaults(suiteName: "brev.test.\(UUID().uuidString)"))
        let queue = UserDefaultsMutationQueue(defaults: defaults, storageKey: "q")
        let capture = DataCapture()
        let backend = Fixtures.makeBackend(capture: capture, preparer: nil, offlineQueue: queue)
        try await backend.connect()

        await #expect(throws: OutboundCryptoEngineUnavailableError.self) {
            _ = try await backend.send(draft: draft(mode: .signAndEncrypt))
        }
        // Permanent security failure must NOT enter the transient retry queue.
        let pending = try await queue.pending()
        #expect(pending.isEmpty)
        #expect(await capture.submissionData.isEmpty)
    }

    @Test("a plain (.none) send bypasses the preparer and uses the plaintext MIME")
    func noneModeBypassesPreparer() async throws {
        let capture = DataCapture()
        let preparer = CapturingPreparer()
        let backend = Fixtures.makeBackend(capture: capture, preparer: preparer)
        try await backend.connect()

        _ = try await backend.send(draft: draft(mode: .none))

        #expect(preparer.requests.isEmpty)
        let submitted = try #require(await capture.submissionData.first)
        #expect(String(decoding: submitted, as: UTF8.self).contains("Secure subject"))
        // SMTP and Sent-copy still agree on the same bytes.
        #expect(await capture.submissionData == capture.appendData)
    }
}
