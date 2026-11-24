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
import BrevSettings
import Foundation
import Testing

@Suite("SignInCodeArrivalController")
@MainActor
struct SignInCodeArrivalControllerTests {
    private static let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
    private static let spam = Folder(id: "spam", name: "Spam", role: .spam)
    private static let code = "482913"

    @MainActor
    private final class SpyPresenter: SignInCodePresenting {
        var presented: [SignInCodePresentation] = []
        var dismissed: [String] = []
        func present(_ presentation: SignInCodePresentation) { presented.append(presentation) }
        func dismiss(accountID: String) { dismissed.append(accountID) }
    }

    /// Gmail-shaped stub: advertises the capability, answers the trust
    /// assessment from a table, and counts body reads.
    private final class TrustedBackend: MailBackend, SignInTrustAssessing, @unchecked Sendable {
        let account = BrevAccount(id: "acct", displayName: "QA", emailAddress: "qa@example.test")
        let capabilities: BackendCapabilities = []
        var extendedCapabilities: BackendExtendedCapabilities = [.trustedSignInAssessment]
        var assessments: [String: SignInTrustAssessment] = [:]
        var bodies: [String: String] = [:]
        var headers: [MessageHeader] = []
        var folderList: [Folder] = [inbox, spam]
        private let bodyReadLock = NSLock()
        private var recordedBodyReads: [String] = []
        var bodyReads: [String] { bodyReadLock.withLock { recordedBodyReads } }
        private var recordedSubscriptionStarts = 0
        var subscriptionStarts: Int { bodyReadLock.withLock { recordedSubscriptionStarts } }
        private var recordedSubscriptionStops = 0
        var subscriptionStops: Int { bodyReadLock.withLock { recordedSubscriptionStops } }
        private var recordedInboxFocusCount = 0
        var inboxFocusCount: Int { bodyReadLock.withLock { recordedInboxFocusCount } }
        /// Lets a test flip consent while the assessment is in flight.
        var onAssess: (@Sendable () -> Void)?
        var onHeaders: (@Sendable () -> Void)?

        func signInTrustAssessment(for messageID: String) async -> SignInTrustAssessment {
            onAssess?()
            return assessments[messageID] ?? .unavailable(.noTrustedHeader)
        }

        func focusInboxForBackgroundSubscription() async {
            bodyReadLock.withLock { recordedInboxFocusCount += 1 }
        }

        func connect() async throws {}
        func disconnect() async {}
        func folders() async throws -> [Folder] { folderList }
        func refresh(folder: Folder) async throws {}
        func currentMailbox() async throws -> Mailbox {
            Mailbox(id: account.id, email: account.emailAddress, displayName: account.displayName, isPrimary: true)
        }

        func switchMailbox(id: String) async throws {}
        func messages(in folder: Folder, pageToken: String?) async throws
            -> (headers: [MessageHeader], nextPageToken: String?) {
            onHeaders?()
            return (headers, nil)
        }

        func body(for messageID: String) async throws -> MessageBody {
            bodyReadLock.withLock { recordedBodyReads.append(messageID) }
            return MessageBody(messageID: messageID, plainText: bodies[messageID])
        }

        func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {}
        func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {}
        func move(messageIDs: [String], to folder: Folder) async throws {}
        func delete(messageIDs: [String]) async throws {}
        func save(draft: Draft) async throws -> Draft { draft }
        func discard(draftID: String) async throws {}
        func send(draft: Draft) async throws -> SendResult { SendResult() }
        func search(_ query: SearchQuery) async throws -> [MessageHeader] { [] }
        func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
            throw MailBackendError.notSupported(capabilities)
        }

        func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {}
        func subscribeToChanges() -> AsyncStream<MailEvent> {
            bodyReadLock.withLock { recordedSubscriptionStarts += 1 }
            return AsyncStream { [weak self] continuation in
                continuation.onTermination = { [weak self] _ in
                    self?.bodyReadLock.withLock { self?.recordedSubscriptionStops += 1 }
                }
            }
        }

        func sourceID(for mailbox: Mailbox) -> MailSourceID {
            MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        }

        func extensionService<Service>(_ type: Service.Type) -> Service? { nil }
    }

    /// Settings can be mutated from the stub's non-isolated assessment
    /// while the controller reads them on the main actor, so access goes
    /// through a lock.
    private final class ConsentBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = SignInCodeSettings()

        var settings: SignInCodeSettings {
            lock.withLock { storage }
        }

        func mutate(_ body: (inout SignInCodeSettings) -> Void) {
            lock.withLock { body(&storage) }
        }
    }

    private func makeBackend(consentedCode: Bool = true) -> (TrustedBackend, ConsentBox) {
        let backend = TrustedBackend()
        backend.assessments["m1"] = .pass(fromDomain: "example.test")
        backend.bodies["m1"] = "Your verification code is \(Self.code)"
        backend.headers = [
            MessageHeader(
                id: "m1", threadID: "t1", folderID: "inbox",
                from: Correspondent(name: "Example Login", email: "no-reply@example.test"),
                subject: "Code", snippet: "", date: Date()
            ),
        ]
        let box = ConsentBox()
        box.mutate {
            $0.setAccountOverride(accountID: "acct", codesEnabled: consentedCode, linksEnabled: false)
        }
        return (backend, box)
    }

    @Test("a consented, trusted, fresh inbox message presents its code with the sender name")
    func presentsCode() async {
        let (backend, box) = makeBackend()
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.count == 1)
        #expect(presenter.presented.first?.content == .code(Self.code))
        #expect(presenter.presented.first?.sender == "Example Login")
        #expect(presenter.presented.first?.timeout == SignInCodeSettings.panelTimeout)
        #expect(backend.bodyReads == ["m1"])
        #expect(controller.pendingInspectionCount == 0)
    }

    @Test("no consent means no assessment and no body read")
    func noConsent() async {
        let (backend, box) = makeBackend(consentedCode: false)
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.isEmpty)
        #expect(backend.bodyReads.isEmpty)
    }

    @Test("an account without the capability never reads a body even with consent")
    func noCapability() async {
        let (backend, box) = makeBackend()
        backend.extendedCapabilities = []
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.isEmpty)
        #expect(backend.bodyReads.isEmpty)
    }

    @Test("spam, untrusted and stale messages never reach the body read")
    func gatesFailClosed() async {
        let (backend, box) = makeBackend()
        backend.assessments["m2"] = .unavailable(.stale)
        backend.bodies["m2"] = backend.bodies["m1"]
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "spam", messageIDs: ["m1"]), from: backend)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m2", "m3"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.isEmpty)
        #expect(backend.bodyReads.isEmpty)
    }

    @Test("a link is only presented when the links opt-in is on")
    func linkConsentIsSeparate() async {
        let (backend, box) = makeBackend()
        backend.bodies["m1"] = "Sign in to login.example.test: https://login.example.test/session"
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.isEmpty)

        box.mutate { $0.setAccountOverride(accountID: "acct", codesEnabled: false, linksEnabled: true) }
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(
            presenter.presented.map(\.content)
                == [.link(destination: "https://login.example.test/session", host: "login.example.test")]
        )
    }

    @Test("consent withdrawn during the assessment stops before the body read")
    func consentRecheckedBeforeBodyRead() async {
        let (backend, box) = makeBackend()
        backend.onAssess = {
            box.mutate { $0.setAccountOverride(accountID: "acct", codesEnabled: false, linksEnabled: false) }
        }
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.isEmpty)
        #expect(backend.bodyReads.isEmpty)
    }

    @Test("withdrawing code consent during sender lookup does not use link consent")
    func specificConsentRecheckedBeforePresentation() async {
        let (backend, box) = makeBackend()
        backend.onHeaders = {
            box.mutate { $0.setAccountOverride(accountID: "acct", codesEnabled: false, linksEnabled: true) }
        }
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(backend.bodyReads == ["m1"])
        #expect(presenter.presented.isEmpty)
    }

    @Test("cancel dismisses the account's panel and drops pending work")
    func cancelDismisses() async {
        let (backend, box) = makeBackend()
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        controller.cancel(accountID: "acct")
        await controller.settle()
        #expect(presenter.dismissed == ["acct"])
    }

    @Test("a burst inspects at most five messages")
    func burstCap() async {
        let (backend, box) = makeBackend()
        for index in 2 ... 9 {
            backend.assessments["m\(index)"] = .pass(fromDomain: "example.test")
            backend.bodies["m\(index)"] = backend.bodies["m1"]
        }
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(
            .messagesAdded(folderID: "inbox", messageIDs: (1 ... 9).map { "m\($0)" }),
            from: backend
        )
        await controller.settle()
        #expect(backend.bodyReads.count == SignInCodeArrivalController.maxMessagesPerEvent)
        #expect(controller.pendingInspectionCount == 0)
    }

    @Test("presentations redact themselves and HTML-only bodies are ignored")
    func redactionAndPlainTextOnly() async {
        let (backend, box) = makeBackend()
        backend.bodies["m1"] = nil
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.isEmpty)

        let presentation = SignInCodePresentation(
            accountID: "acct", messageID: "m1", sender: "x", content: .code(Self.code), timeout: 60
        )
        #expect(!String(describing: presentation).contains(Self.code))
        #expect(!String(reflecting: presentation).contains(Self.code))
        #expect(Mirror(reflecting: presentation).children.isEmpty)
    }

    @Test(
        "generic IMAP account extracts verified sign-in code via subscribeToChanges and drops unverified messages without body read"
    )
    func genericIMAPEndToEndVerification() async throws {
        let now = Date()
        let account = BrevAccount(
            id: BrevAccount.imapSMTPAccountID(forEmailAddress: "alex@fastmail.com"),
            displayName: "Fastmail",
            emailAddress: "alex@fastmail.com"
        )
        let config = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap, host: "imap.fastmail.com", port: 993, tlsMode: .implicit, authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp, host: "smtp.fastmail.com", port: 465, tlsMode: .implicit, authentication: .password
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: account.emailAddress,
            outgoingUsername: account.emailAddress,
            secret: "app-password",
            authentication: .password
        )
        final class StateBox: @unchecked Sendable {
            private let lock = NSLock()
            var listings: [IMAPMessageListing] = []
            var bodyReadUIDs: [Int] = []
            func setListings(_ value: [IMAPMessageListing]) { lock.withLock { listings = value } }
            func currentListings() -> [IMAPMessageListing] { lock.withLock { listings } }
            func recordBodyRead(_ uid: Int) { lock.withLock { bodyReadUIDs.append(uid) } }
            func reads() -> [Int] { lock.withLock { bodyReadUIDs } }
        }
        let stateBox = StateBox()
        let headersByUID: [Int: String] = [
            11: """
            Authentication-Results: mx2.messagingengine.com; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
            From: Bank Login <alerts@bank.example>\r
            \r
            """,
            12: """
            Authentication-Results: mx2.messagingengine.com; dmarc=fail header.from=bank.example; dkim=fail\r
            Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example\r
            From: Bank Login <alerts@bank.example>\r
            \r
            """,
            13: """
            Authentication-Results: mx2.messagingengine.com; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
            From: Bank Login <alerts@bank.example>\r
            \r
            """,
            14: """
            Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example\r
            From: Bank Login <alerts@bank.example>\r
            \r
            """
        ]
        func listing(_ uid: Int, internalDate: Date) -> IMAPMessageListing {
            IMAPMessageListing(
                uid: uid,
                messageID: "<m-\(uid)@bank.example>",
                subject: "Sign-in code",
                from: Correspondent(name: "Bank Login", email: "alerts@bank.example"),
                to: [Correspondent(email: account.emailAddress)],
                cc: [],
                bcc: [],
                date: internalDate,
                internalDate: internalDate,
                isRead: false,
                isFlagged: false,
                isAnswered: false
            )
        }
        stateBox.setListings([listing(10, internalDate: now.addingTimeInterval(-3600))])

        let expectedCode = Self.code
        let backend = IMAPSMTPBackend(
            account: account,
            configuration: config,
            credential: credential,
            listFolders: { _, _ in
                [IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox)]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: stateBox.currentListings())
            },
            fetchMessageBody: { _, _, _, uid in
                stateBox.recordBodyRead(uid)
                return MessageBody(messageID: "INBOX:\(uid)", plainText: "Your verification code is \(expectedCode)")
            },
            fetchMessagePart: { _, _, _, uid, _, _ in
                Data((headersByUID[uid] ?? "").utf8)
            },
            signInTrustNow: { now }
        )
        #expect(backend.extendedCapabilities.contains(.trustedSignInAssessment))

        let box = ConsentBox()
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        try await backend.connect()
        try await backend.refresh(folder: inbox)

        // Subscribe to real MailEvents emitted by IMAPSMTPBackend.subscribeToChanges().
        var receivedAddedBatches: [[String]] = []
        let subscriptionTask = Task { @MainActor in
            for await event in backend.subscribeToChanges() {
                if case .messagesAdded(_, let ids) = event {
                    receivedAddedBatches.append(ids)
                    controller.handle(event, from: backend)
                }
            }
        }
        await Task.yield()

        // Off by default: real refresh emits .messagesAdded, but no body read or presentation occurs.
        stateBox.setListings([
            listing(11, internalDate: now),
            listing(12, internalDate: now),
            listing(10, internalDate: now.addingTimeInterval(-3600))
        ])
        try await backend.refresh(folder: inbox)
        for _ in 0 ..< 50 where receivedAddedBatches.count < 1 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await controller.settle()
        #expect(receivedAddedBatches.count == 1)
        #expect(presenter.presented.isEmpty)
        #expect(stateBox.reads().isEmpty)

        // Opt in for this generic IMAP account: verified UID 13 presents via subscribeToChanges;
        // forged foreign authserv-id UID 14 fails closed and never reads its body.
        box.mutate { $0.setAccountOverride(accountID: account.id, codesEnabled: true, linksEnabled: false) }
        stateBox.setListings([
            listing(13, internalDate: now),
            listing(14, internalDate: now),
            listing(11, internalDate: now),
            listing(12, internalDate: now),
            listing(10, internalDate: now.addingTimeInterval(-3600))
        ])
        try await backend.refresh(folder: inbox)
        for _ in 0 ..< 50 where receivedAddedBatches.count < 2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await controller.settle()
        subscriptionTask.cancel()
        await subscriptionTask.value

        #expect(presenter.presented.count == 1)
        #expect(presenter.presented.first?.messageID == "INBOX:13")
        #expect(presenter.presented.first?.content == .code(Self.code))
        #expect(presenter.presented.first?.sender == "Bank Login")
        #expect(stateBox.reads() == [13])
    }

    #if os(macOS)
    private actor StubTokenStore: TokenStore {
        private var tokens: [String: Token] = [:]
        func token(for accountID: String) -> Token? { tokens[accountID] }
        func setToken(_ token: Token, for accountID: String) { tokens[accountID] = token }
        func clearToken(for accountID: String) { tokens[accountID] = nil }
    }

    @Test("AppSession never starts a competing subscription while a mailbox window is open or opt-ins are off")
    func sessionSubscriptionRespectsWindowOwnershipAndOptIns() async {
        let backend = TrustedBackend()
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: StubTokenStore(),
            notificationCenter: NotificationCenter(),
            loginCoordinator: {
                AppSession.LoginResult(backend: backend, account: backend.account)
            }
        )
        session.mailboxWindowDidOpen()
        await session.signIn()

        var backgroundOff = NotificationSettings.defaults
        backgroundOff.backgroundMailEnabled = false
        var backgroundOn = NotificationSettings.defaults
        backgroundOn.backgroundMailEnabled = true

        let consentOff = SignInCodeSettings.defaults
        var consentOn = SignInCodeSettings.defaults
        consentOn.setAccountOverride(accountID: backend.account.id, codesEnabled: true, linksEnabled: false)

        // With a mailbox window open, AppSession must not open a second IDLE stream.
        session.syncSignInCodeArrivalSubscriptions(
            notificationSettings: backgroundOn,
            signInCodeSettings: consentOn
        )
        await Task.yield()
        #expect(backend.subscriptionStarts == 0)

        // Closing the window with background mail or sign-in consent off starts no stream.
        session.mailboxWindowDidClose()
        session.syncSignInCodeArrivalSubscriptions(
            notificationSettings: backgroundOff,
            signInCodeSettings: consentOn
        )
        session.syncSignInCodeArrivalSubscriptions(
            notificationSettings: backgroundOn,
            signInCodeSettings: consentOff
        )
        await Task.yield()
        #expect(backend.subscriptionStarts == 0)

        // Only when windowless + background mail on + account opted-in + trusted capability does one stream start,
        // and it refocuses the background subscription on Inbox.
        session.syncSignInCodeArrivalSubscriptions(
            notificationSettings: backgroundOn,
            signInCodeSettings: consentOn
        )
        for _ in 0 ..< 20 where backend.subscriptionStarts == 0 {
            await Task.yield()
        }
        #expect(backend.subscriptionStarts == 1)
        #expect(backend.inboxFocusCount == 1)

        // Re-syncing for the same backend does not spawn a duplicate stream.
        session.syncSignInCodeArrivalSubscriptions(
            notificationSettings: backgroundOn,
            signInCodeSettings: consentOn
        )
        await Task.yield()
        #expect(backend.subscriptionStarts == 1)

        // Reopening a mailbox window terminates the session's background stream
        // so the mailbox view resumes exclusive ownership with zero overlap.
        session.mailboxWindowDidOpen()
        await Task.yield()
        #expect(backend.subscriptionStops == 1)
    }
    #endif
}
