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
    private(set) var validatedRequests: [OutboundMessageSecurityRequest] = []
    private(set) var requests: [OutboundMessageSecurityRequest] = []
    private(set) var receivedPlaintext: [Data] = []
    private let validateHandler: (@Sendable (OutboundMessageSecurityRequest) throws -> Void)?
    private let handler: (@Sendable (Data, OutboundMessageSecurityRequest) throws -> Data)?

    init(
        validateHandler: (@Sendable (OutboundMessageSecurityRequest) throws -> Void)? = nil,
        handler: (@Sendable (Data, OutboundMessageSecurityRequest) throws -> Data)? = nil
    ) {
        self.validateHandler = validateHandler
        self.handler = handler
    }

    func validate(request: OutboundMessageSecurityRequest) async throws {
        lock.withLock {
            validatedRequests.append(request)
        }
        try validateHandler?(request)
    }

    func prepare(mimeData: Data, request: OutboundMessageSecurityRequest) async throws -> Data {
        lock.withLock {
            requests.append(request)
            receivedPlaintext.append(mimeData)
        }
        if let handler {
            return try handler(mimeData, request)
        }
        return Self.preparedMarker
    }
}

private actor DataCapture {
    private(set) var submissions: [SMTPMessageSubmission] = []
    private(set) var submissionData: [Data] = []
    private(set) var appendData: [Data] = []
    func recordSubmission(_ submission: SMTPMessageSubmission) {
        submissions.append(submission)
        submissionData.append(submission.messageData)
    }

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
                await capture.recordSubmission(submission)
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

    @Test("IMAPSMTPBackend advertises outboundSMIME only when a preparer is wired")
    func advertisesOutboundSMIMECapabilityOnlyWhenPreparerIsWired() {
        let capture = DataCapture()
        let withPreparer = Fixtures.makeBackend(capture: capture, preparer: CapturingPreparer())
        let withoutPreparer = Fixtures.makeBackend(capture: capture, preparer: nil)

        #expect(withPreparer.extendedCapabilities.contains(.outboundSMIME))
        #expect(!withoutPreparer.extendedCapabilities.contains(.outboundSMIME))
    }

    @Test("encrypted send isolates Bcc recipients into separate envelopes without leaking Bcc metadata to To/Cc")
    func encryptedSendIsolatesBccRecipientsIntoSeparateEnvelopes() async throws {
        let capture = DataCapture()
        let preparer = CapturingPreparer(handler: { _, request in
            let tag = "ENV:to=\(request.to.joined(separator: ","));cc=\(request.cc.joined(separator: ","));bcc=\(request.bcc.joined(separator: ","))"
            return Data(tag.utf8)
        })
        let backend = Fixtures.makeBackend(capture: capture, preparer: preparer)
        try await backend.connect()

        let bccDraft = Draft(
            id: "draft-bcc-enc",
            to: [Correspondent(email: "bob@example.org")],
            cc: [Correspondent(email: "carol@example.org")],
            bcc: [
                Correspondent(email: "secret1@example.org"),
                Correspondent(email: "secret2@example.org")
            ],
            subject: "Confidential",
            htmlBody: "<p>Top secret</p>",
            securityMode: .signAndEncrypt
        )

        _ = try await backend.send(draft: bccDraft)

        let submissions = await capture.submissions
        #expect(submissions.count == 3)
        #expect(submissions[0].recipientEmails == ["bob@example.org", "carol@example.org"])
        #expect(String(decoding: submissions[0].messageData, as: UTF8.self) == "ENV:to=bob@example.org;cc=carol@example.org;bcc=")
        #expect(submissions[1].recipientEmails == ["secret1@example.org"])
        #expect(String(decoding: submissions[1].messageData, as: UTF8.self) == "ENV:to=;cc=;bcc=secret1@example.org")
        #expect(submissions[2].recipientEmails == ["secret2@example.org"])
        #expect(String(decoding: submissions[2].messageData, as: UTF8.self) == "ENV:to=;cc=;bcc=secret2@example.org")
        // Sent copy stores the visible encrypted envelope (never a Bcc-leaking envelope).
        #expect(await capture.appendData == [submissions[0].messageData])
    }

    @Test("encrypted send with Bcc fails closed before any SMTP send if a Bcc certificate is missing")
    func encryptedBccSendFailsClosedBeforeAnySubmission() async throws {
        let capture = DataCapture()
        let preparer = CapturingPreparer(
            validateHandler: { request in
                if request.bcc.contains("missing@example.org") {
                    throw OutboundMessageSecurityError.missingEncryptionRecipients(["missing@example.org"])
                }
            },
            handler: { _, _ in Data("OK".utf8) }
        )
        let backend = Fixtures.makeBackend(capture: capture, preparer: preparer)
        try await backend.connect()

        let bccDraft = Draft(
            id: "draft-bcc-missing",
            to: [Correspondent(email: "bob@example.org")],
            bcc: [Correspondent(email: "missing@example.org")],
            subject: "Confidential",
            htmlBody: "<p>Top secret</p>",
            securityMode: .encrypt
        )

        await #expect(throws: OutboundMessageSecurityError.missingEncryptionRecipients(["missing@example.org"])) {
            _ = try await backend.send(draft: bccDraft)
        }
        // Pre-validation failed closed BEFORE preparing or transmitting any envelope!
        #expect(preparer.requests.isEmpty)
        #expect(await capture.submissions.isEmpty)
        #expect(await capture.appendData.isEmpty)
    }

    @Test("partial Bcc retry skips already-accepted envelopes without duplicating earlier recipients")
    func partialBccRetrySkipsAlreadyAcceptedEnvelopes() async throws {
        let suiteName = "brev.ledger.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ledger = SentMessageLedger(defaults: defaults)

        let capture = DataCapture()
        let preparer = CapturingPreparer(handler: { _, request in
            let tag = "ENV:to=\(request.to.joined(separator: ","));bcc=\(request.bcc.joined(separator: ","))"
            return Data(tag.utf8)
        })

        actor FlakySMTP {
            private var failedOnce = false
            func handle(_ submission: SMTPMessageSubmission) throws -> SendResult {
                if submission.recipientEmails == ["secret@example.org"], !failedOnce {
                    failedOnce = true
                    throw URLError(.networkConnectionLost)
                }
                return SendResult(sentMessageID: "smtp-ok-\(submission.recipientEmails.joined(separator: ","))")
            }
        }
        let flakySMTP = FlakySMTP()

        func makeBackendWithLedger() -> IMAPSMTPBackend {
            IMAPSMTPBackend(
                account: Fixtures.account,
                configuration: Fixtures.configuration,
                credential: Fixtures.credential,
                listFolders: { _, _ in [
                    IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
                    IMAPFolderListing(path: "Sent", displayName: "Sent", delimiter: "/", flags: ["sent"], role: .sent),
                ] },
                sendMessage: { _, _, submission in
                    let result = try await flakySMTP.handle(submission)
                    await capture.recordSubmission(submission)
                    return result
                },
                appendSentMessage: { _, _, _, messageData, _ in
                    await capture.recordAppend(messageData)
                    return 1
                },
                outboundMessagePreparer: preparer,
                sentMessageLedger: ledger
            )
        }

        let bccDraft = Draft(
            id: "draft-bcc-partial-retry",
            to: [Correspondent(email: "bob@example.org")],
            bcc: [Correspondent(email: "secret@example.org")],
            subject: "Retry Idempotency",
            htmlBody: "<p>Body</p>",
            securityMode: .encrypt
        )

        // Attempt 1: visible To envelope succeeds, Bcc envelope fails transiently.
        let firstAttemptBackend = makeBackendWithLedger()
        try await firstAttemptBackend.connect()
        await #expect(throws: Error.self) {
            _ = try await firstAttemptBackend.send(draft: bccDraft)
        }
        #expect(await capture.submissions.map(\.recipientEmails) == [["bob@example.org"]])

        // Attempt 2 (even on a freshly recreated backend using the same persisted ledger):
        // skips already-accepted To envelope and sends ONLY the remaining Bcc envelope!
        let retryBackend = makeBackendWithLedger()
        try await retryBackend.connect()
        _ = try await retryBackend.send(draft: bccDraft)

        let allSubmissions = await capture.submissions
        #expect(allSubmissions.map(\.recipientEmails) == [["bob@example.org"], ["secret@example.org"]])
        #expect(await capture.appendData.count == 1)
    }

    @Test("adding a new visible Cc recipient after partial Bcc failure delivers only new Cc and Bcc without re-sending To")
    func partialBccRetryWithAddedVisibleCcSkipsAcceptedTo() async throws {
        let suiteName = "brev.ledger.cc.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ledger = SentMessageLedger(defaults: defaults)

        let capture = DataCapture()
        let preparer = CapturingPreparer(handler: { _, request in
            let tag = "ENV:to=\(request.to.joined(separator: ","));cc=\(request.cc.joined(separator: ","));bcc=\(request.bcc.joined(separator: ","))"
            return Data(tag.utf8)
        })

        actor RejectOnceBccSMTP {
            private var rejected = false
            func handle(_ submission: SMTPMessageSubmission) throws -> SendResult {
                if submission.recipientEmails == ["secret@example.org"], !rejected {
                    rejected = true
                    throw URLError(.networkConnectionLost)
                }
                return SendResult(sentMessageID: "ok-\(submission.recipientEmails.joined(separator: ","))")
            }
        }
        let smtp = RejectOnceBccSMTP()

        func makeBackendWithLedger() -> IMAPSMTPBackend {
            IMAPSMTPBackend(
                account: Fixtures.account,
                configuration: Fixtures.configuration,
                credential: Fixtures.credential,
                listFolders: { _, _ in [
                    IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
                    IMAPFolderListing(path: "Sent", displayName: "Sent", delimiter: "/", flags: ["sent"], role: .sent),
                ] },
                sendMessage: { _, _, submission in
                    let result = try await smtp.handle(submission)
                    await capture.recordSubmission(submission)
                    return result
                },
                appendSentMessage: { _, _, _, messageData, _ in
                    await capture.recordAppend(messageData)
                    return 1
                },
                outboundMessagePreparer: preparer,
                sentMessageLedger: ledger
            )
        }

        let initialDraft = Draft(
            id: "draft-bcc-add-cc",
            to: [Correspondent(email: "bob@example.org")],
            bcc: [Correspondent(email: "secret@example.org")],
            subject: "Same Content",
            htmlBody: "<p>Unchanged body</p>",
            securityMode: .encrypt
        )

        // Attempt 1: Bob succeeds, secret fails.
        let attempt1 = makeBackendWithLedger()
        try await attempt1.connect()
        await #expect(throws: Error.self) {
            _ = try await attempt1.send(draft: initialDraft)
        }
        #expect(await capture.submissions.map(\.recipientEmails) == [["bob@example.org"]])

        // Attempt 2: User adds Alice to Cc with the same message content & draft ID.
        // Bob must NOT be re-sent; Alice and secret each receive their envelope.
        var retryDraft = initialDraft
        retryDraft.cc = [Correspondent(email: "alice@example.org")]

        let attempt2 = makeBackendWithLedger()
        try await attempt2.connect()
        _ = try await attempt2.send(draft: retryDraft)

        let submissions = await capture.submissions
        #expect(submissions.map(\.recipientEmails) == [
            ["bob@example.org"],
            ["alice@example.org"],
            ["secret@example.org"],
        ])
        #expect(String(decoding: submissions[1].messageData, as: UTF8.self) == "ENV:to=;cc=alice@example.org;bcc=")
        #expect(String(decoding: submissions[2].messageData, as: UTF8.self) == "ENV:to=;cc=;bcc=secret@example.org")
        #expect(await capture.appendData.count == 1)
    }

    @Test("removing the last Bcc after partial failure does not re-send already-accepted To; editing content starts fresh")
    func partialBccRetryAfterRemovingLastBccDoesNotResendVisible() async throws {
        let suiteName = "brev.ledger.dropbcc.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ledger = SentMessageLedger(defaults: defaults)

        let capture = DataCapture()
        let preparer = CapturingPreparer(handler: { _, request in
            let tag = "ENV:to=\(request.to.joined(separator: ","));bcc=\(request.bcc.joined(separator: ","))"
            return Data(tag.utf8)
        })

        func makeBackendWithLedger(failBcc: Bool) -> IMAPSMTPBackend {
            IMAPSMTPBackend(
                account: Fixtures.account,
                configuration: Fixtures.configuration,
                credential: Fixtures.credential,
                listFolders: { _, _ in [
                    IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
                    IMAPFolderListing(path: "Sent", displayName: "Sent", delimiter: "/", flags: ["sent"], role: .sent),
                ] },
                sendMessage: { _, _, submission in
                    if failBcc, submission.recipientEmails == ["secret@example.org"] {
                        throw URLError(.networkConnectionLost)
                    }
                    await capture.recordSubmission(submission)
                    return SendResult(sentMessageID: "ok")
                },
                appendSentMessage: { _, _, _, messageData, _ in
                    await capture.recordAppend(messageData)
                    return 1
                },
                outboundMessagePreparer: preparer,
                sentMessageLedger: ledger
            )
        }

        let initialDraft = Draft(
            id: "draft-bcc-remove-last",
            to: [Correspondent(email: "bob@example.org")],
            bcc: [Correspondent(email: "secret@example.org")],
            subject: "Same Subject",
            htmlBody: "<p>Original body</p>",
            securityMode: .encrypt
        )

        // Attempt 1: Bob succeeds, secret fails.
        let attempt1 = makeBackendWithLedger(failBcc: true)
        try await attempt1.connect()
        await #expect(throws: Error.self) {
            _ = try await attempt1.send(draft: initialDraft)
        }
        #expect(await capture.submissions.map(\.recipientEmails) == [["bob@example.org"]])

        // Attempt 2: User edits body BEFORE removing Bcc — content fingerprint changes,
        // so Bob receives the updated body when retrying (tested on a second draft below),
        // while keeping identical content and removing the last Bcc sends 0 SMTP envelopes!
        var withoutBcc = initialDraft
        withoutBcc.bcc = []
        let attempt2 = makeBackendWithLedger(failBcc: false)
        try await attempt2.connect()
        _ = try await attempt2.send(draft: withoutBcc)

        // Zero additional SMTP sends for Bob; Sent copy was appended once.
        #expect(await capture.submissions.map(\.recipientEmails) == [["bob@example.org"]])
        #expect(await capture.appendData.count == 1)

        // Verify content-fingerprint sensitivity: a partial failure followed by a body edit
        // treats the edited draft as a new delivery snapshot and delivers fresh to Bob.
        let editedInitial = Draft(
            id: "draft-bcc-edited-content",
            to: [Correspondent(email: "bob@example.org")],
            bcc: [Correspondent(email: "secret@example.org")],
            subject: "V1",
            htmlBody: "<p>First version</p>",
            securityMode: .encrypt
        )
        let attempt3 = makeBackendWithLedger(failBcc: true)
        try await attempt3.connect()
        await #expect(throws: Error.self) {
            _ = try await attempt3.send(draft: editedInitial)
        }
        var editedRetry = editedInitial
        editedRetry.htmlBody = "<p>Second version</p>"
        editedRetry.bcc = []
        let attempt4 = makeBackendWithLedger(failBcc: false)
        try await attempt4.connect()
        _ = try await attempt4.send(draft: editedRetry)

        #expect(await capture.submissions.map(\.recipientEmails) == [
            ["bob@example.org"],
            ["bob@example.org"],
            ["bob@example.org"],
        ])

        // Toggling Request Read Receipt also changes the delivery content fingerprint
        // and starts a fresh delivery snapshot.
        let receiptInitial = Draft(
            id: "draft-bcc-read-receipt",
            to: [Correspondent(email: "bob@example.org")],
            bcc: [Correspondent(email: "secret@example.org")],
            subject: "Receipt check",
            htmlBody: "<p>Same body</p>",
            securityMode: .encrypt
        )
        let attempt5 = makeBackendWithLedger(failBcc: true)
        try await attempt5.connect()
        await #expect(throws: Error.self) {
            _ = try await attempt5.send(draft: receiptInitial)
        }
        var receiptRetry = receiptInitial
        receiptRetry.readReceiptRequest = ReadReceiptRequest(notificationTo: "person@example.org")
        receiptRetry.bcc = []
        let attempt6 = makeBackendWithLedger(failBcc: false)
        try await attempt6.connect()
        _ = try await attempt6.send(draft: receiptRetry)

        #expect(await capture.submissions.map(\.recipientEmails) == [
            ["bob@example.org"],
            ["bob@example.org"],
            ["bob@example.org"],
            ["bob@example.org"],
            ["bob@example.org"],
        ])

        // Draft-level completion prunes intermediate per-recipient entries from SentMessageLedger
        // so completed drafts consume only 1 slot of the ledger cap.
        let storedLedger = try #require(defaults.data(forKey: "sentMessageLedger.\(Fixtures.account.id)"))
        let entries = try JSONDecoder().decode([String].self, from: storedLedger)
        #expect(entries.contains("draft-bcc-remove-last"))
        #expect(!entries.contains(where: { $0.hasPrefix("draft-bcc-remove-last#fp:") }))
        #expect(entries.contains("draft-bcc-read-receipt"))
        #expect(!entries.contains(where: { $0.hasPrefix("draft-bcc-read-receipt#fp:") }))
    }

    @Test("fallback Sent copy failure aborts before sending pending Bcc or marking draft complete")
    func fallbackSentCopyPreparedBeforePendingSubmissionOrCompletion() async throws {
        let suiteName = "brev.ledger.sentcopy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ledger = SentMessageLedger(defaults: defaults)

        let capture = DataCapture()
        final class FlagBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            var isSet: Bool { lock.withLock { value } }
            func set(_ newValue: Bool) { lock.withLock { value = newValue } }
        }
        let bobCertRemoved = FlagBox()
        let preparer = CapturingPreparer(
            validateHandler: { request in
                if bobCertRemoved.isSet, request.to.contains("bob@example.org") {
                    throw OutboundMessageSecurityError.missingEncryptionRecipients(["bob@example.org"])
                }
            },
            handler: { _, request in
                if bobCertRemoved.isSet, request.to.contains("bob@example.org") {
                    throw OutboundMessageSecurityError.missingEncryptionRecipients(["bob@example.org"])
                }
                return Data("ENV:to=\(request.to.joined(separator: ","));bcc=\(request.bcc.joined(separator: ","))".utf8)
            }
        )

        func makeBackend(failBcc: Bool) -> IMAPSMTPBackend {
            IMAPSMTPBackend(
                account: Fixtures.account,
                configuration: Fixtures.configuration,
                credential: Fixtures.credential,
                listFolders: { _, _ in [
                    IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
                    IMAPFolderListing(path: "Sent", displayName: "Sent", delimiter: "/", flags: ["sent"], role: .sent),
                ] },
                sendMessage: { _, _, submission in
                    if failBcc, submission.recipientEmails == ["secret@example.org"] {
                        throw URLError(.networkConnectionLost)
                    }
                    await capture.recordSubmission(submission)
                    return SendResult(sentMessageID: "ok")
                },
                appendSentMessage: { _, _, _, messageData, _ in
                    await capture.recordAppend(messageData)
                    return 1
                },
                outboundMessagePreparer: preparer,
                sentMessageLedger: ledger
            )
        }

        let bccDraft = Draft(
            id: "draft-fallback-sent-copy",
            to: [Correspondent(email: "bob@example.org")],
            bcc: [Correspondent(email: "secret@example.org")],
            subject: "Sent Copy Precheck",
            htmlBody: "<p>Secret</p>",
            securityMode: .encrypt
        )

        // Attempt 1: Bob accepted, secret fails transiently.
        let attempt1 = makeBackend(failBcc: true)
        try await attempt1.connect()
        await #expect(throws: Error.self) {
            _ = try await attempt1.send(draft: bccDraft)
        }
        #expect(await capture.submissions.map(\.recipientEmails) == [["bob@example.org"]])

        // Before Attempt 2, Bob's certificate is removed. Preparing the fallback
        // visible Sent archive MUST fail before sending secret or marking draft complete.
        bobCertRemoved.set(true)
        let attempt2 = makeBackend(failBcc: false)
        try await attempt2.connect()
        await #expect(throws: OutboundMessageSecurityError.missingEncryptionRecipients(["bob@example.org"])) {
            _ = try await attempt2.send(draft: bccDraft)
        }

        #expect(await capture.submissions.map(\.recipientEmails) == [["bob@example.org"]])
        #expect(await capture.appendData.isEmpty)
        #expect(!ledger.contains(draftID: bccDraft.id, accountID: Fixtures.account.id))
    }

    @Test("signing-only send preserves SMTP local-part case while deduplicating domain case")
    func signingOnlySendPreservesSMTPLocalPartCase() async throws {
        let capture = DataCapture()
        let preparer = CapturingPreparer()
        let backend = Fixtures.makeBackend(capture: capture, preparer: preparer)
        try await backend.connect()

        let caseSensitiveDraft = Draft(
            id: "draft-case-sensitive-rcpt",
            to: [
                Correspondent(email: "Sales@example.org"),
                Correspondent(email: "sales@example.org"),
                Correspondent(email: "Sales@EXAMPLE.ORG"),
            ],
            subject: "Case-sensitive local parts",
            htmlBody: "<p>Signed announcement</p>",
            securityMode: .sign
        )

        _ = try await backend.send(draft: caseSensitiveDraft)

        let submissions = await capture.submissions
        #expect(submissions.count == 1)
        #expect(submissions[0].recipientEmails == ["Sales@example.org", "sales@example.org"])
    }
}
