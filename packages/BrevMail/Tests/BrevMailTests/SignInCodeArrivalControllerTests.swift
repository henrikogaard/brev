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
        private(set) var bodyReads: [String] = []
        /// Lets a test flip consent while the assessment is in flight.
        var onAssess: (@Sendable () -> Void)?

        func signInTrustAssessment(for messageID: String) async -> SignInTrustAssessment {
            onAssess?()
            return assessments[messageID] ?? .unavailable(.noTrustedHeader)
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
            -> (headers: [MessageHeader], nextPageToken: String?) { (headers, nil) }
        func body(for messageID: String) async throws -> MessageBody {
            bodyReads.append(messageID)
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
        func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }
        func sourceID(for mailbox: Mailbox) -> MailSourceID {
            MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        }

        func extensionService<Service>(_ type: Service.Type) -> Service? { nil }
    }

    private final class ConsentBox: @unchecked Sendable {
        var settings = SignInCodeSettings()
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
        box.settings.setAccountOverride(accountID: "acct", codesEnabled: consentedCode, linksEnabled: false)
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

        box.settings.setAccountOverride(accountID: "acct", codesEnabled: false, linksEnabled: true)
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
        backend.onAssess = { box.settings.setAccountOverride(accountID: "acct", codesEnabled: false, linksEnabled: false) }
        let presenter = SpyPresenter()
        let controller = SignInCodeArrivalController(settings: { box.settings }, presenter: presenter)
        controller.handle(.messagesAdded(folderID: "inbox", messageIDs: ["m1"]), from: backend)
        await controller.settle()
        #expect(presenter.presented.isEmpty)
        #expect(backend.bodyReads.isEmpty)
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
}
