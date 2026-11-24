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

/// Provider-neutral sign-in trust types, capability gating, and IMAP backend integration (#5).
@Suite("Sign-in trust types and IMAP integration")
struct SignInTrustTests {
    private final class MutableClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date

        init(_ initial: Date = Date()) {
            current = initial
        }

        var now: Date {
            get { lock.withLock { current } }
            set { lock.withLock { current = newValue } }
        }
    }

    private final class ListingBox: @unchecked Sendable {
        private let lock = NSLock()
        private var pagesByFolder: [Folder.ID: [IMAPMessageListing]] = [:]

        func set(_ listings: [IMAPMessageListing], for folderID: Folder.ID) {
            lock.withLock { pagesByFolder[folderID] = listings }
        }

        func listings(for folderID: Folder.ID) -> [IMAPMessageListing] {
            lock.withLock { pagesByFolder[folderID] ?? [] }
        }
    }

    private final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var sections: [String] = []
        private var bodyFetches: [Int] = []

        func recordSection(_ section: String) {
            lock.withLock { sections.append(section) }
        }

        func recordBodyFetch(_ uid: Int) {
            lock.withLock { bodyFetches.append(uid) }
        }

        var fetchedSections: [String] { lock.withLock { sections } }
        var fetchedBodies: [Int] { lock.withLock { bodyFetches } }
    }

    private static let testAccount = BrevAccount(
        id: BrevAccount.imapSMTPAccountID(forEmailAddress: "user@fastmail.example"),
        displayName: "Fastmail",
        emailAddress: "user@fastmail.example"
    )

    private static let testConfig = IMAPAccountConfiguration(
        accountID: testAccount.id,
        emailAddress: testAccount.emailAddress,
        displayName: testAccount.displayName,
        incoming: MailServerSettings(
            kind: .imap,
            host: "imap.fastmail.example",
            port: 993,
            tlsMode: .implicit,
            authentication: .password
        ),
        outgoing: MailServerSettings(
            kind: .smtp,
            host: "smtp.fastmail.example",
            port: 465,
            tlsMode: .implicit,
            authentication: .password
        ),
        credentialID: testAccount.id
    )

    private static let testCredential = MailAccountCredential(
        incomingUsername: "user@fastmail.example",
        outgoingUsername: "user@fastmail.example",
        secret: "app-password",
        authentication: .password
    )

    private static let inboxFolder = Folder(id: "INBOX", name: "Inbox", role: .inbox)
    private static let spamFolder = Folder(id: "Junk", name: "Junk", role: .spam)

    private static func makeListing(uid: Int, date: Date, from: String = "alerts@bank.example") -> IMAPMessageListing {
        IMAPMessageListing(
            uid: uid,
            messageID: "<msg-\(uid)@bank.example>",
            subject: "Sign-in code",
            from: Correspondent(name: "Bank", email: from),
            to: [Correspondent(email: testAccount.emailAddress)],
            cc: [],
            bcc: [],
            date: date,
            isRead: false,
            isFlagged: false,
            isAnswered: false
        )
    }

    private static let inboxListing = IMAPFolderListing(
        path: "INBOX",
        displayName: "Inbox",
        delimiter: "/",
        flags: [],
        role: .inbox
    )

    private static let junkListing = IMAPFolderListing(
        path: "Junk",
        displayName: "Junk",
        delimiter: "/",
        flags: ["\\Junk"],
        role: .spam
    )

    @Test("every failure reason is a stable raw value")
    func failureRawValues() {
        let reasons: [SignInTrustFailure] = [
            .notFreshDelivery, .wrongFolder, .stale, .noTrustedHeader,
            .conflictingTrustedHeaders, .missingDMARC, .duplicateDMARC,
            .dmarcNotPass, .missingAlignedMechanism, .fromMismatch,
            .malformedFrom, .malformedHeader, .unsupportedAccount
        ]
        #expect(Set(reasons.map(\.rawValue)).count == reasons.count)
        #expect(SignInTrustFailure(rawValue: "stale") == .stale)
        #expect(SignInTrustFailure(rawValue: "missingAlignedMechanism") == .missingAlignedMechanism)
    }

    @Test("capability is advertised by IMAPSMTPBackend with listing + header fetch, never by LocalMailBackend")
    func capabilityReporting() {
        #expect(BackendExtendedCapabilities.trustedSignInAssessment.rawValue == 1 << 17)
        let localBackend = LocalMailBackend()
        #expect(!localBackend.extendedCapabilities.contains(.trustedSignInAssessment))

        let minimalIMAP = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.testConfig,
            credential: Self.testCredential,
            listFolders: { _, _ in [] }
        )
        #expect(!minimalIMAP.extendedCapabilities.contains(.trustedSignInAssessment))

        let partBackedIMAP = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.testConfig,
            credential: Self.testCredential,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            fetchMessagePart: { _, _, _, _, _, _ in Data() }
        )
        #expect(partBackedIMAP.extendedCapabilities.contains(.trustedSignInAssessment))

        let sourceBackedIMAP = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.testConfig,
            credential: Self.testCredential,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            fetchMessageSource: { _, _, _, uid in IMAPMessageSource(uid: uid, rawMessage: "") }
        )
        #expect(sourceBackedIMAP.extendedCapabilities.contains(.trustedSignInAssessment))
    }

    @Test("IMAPSMTPBackend passes fresh verified Inbox delivery via BODY.PEEK[HEADER] without body fetch")
    func imapFreshVerifiedInboxPasses() async throws {
        let clock = MutableClock()
        let listingBox = ListingBox()
        let callLog = CallLog()
        let headersByUID = [
            102: """
            Authentication-Results: mx2.messagingengine.com;\r
                dkim=pass header.d=bank.example;\r
                dmarc=pass header.from=bank.example\r
            From: Bank <alerts@bank.example>\r
            Subject: Code\r
            \r
            """
        ]

        listingBox.set([Self.makeListing(uid: 101, date: clock.now.addingTimeInterval(-3600))], for: "INBOX")

        let backend = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.testConfig,
            credential: Self.testCredential,
            listFolders: { _, _ in
                [Self.inboxListing, Self.junkListing]
            },
            listMessages: { _, _, folderID, _, _ in
                IMAPMessageListingPage(messages: listingBox.listings(for: folderID))
            },
            fetchMessageBody: { _, _, _, uid in
                callLog.recordBodyFetch(uid)
                return MessageBody(messageID: "INBOX:\(uid)", plainText: "Code 123456")
            },
            fetchMessagePart: { _, _, _, uid, section, _ in
                callLog.recordSection(section)
                return Data((headersByUID[uid] ?? "").utf8)
            },
            signInTrustNow: { clock.now }
        )

        try await backend.connect()
        // Initial listing seeds known IDs and never marks pre-existing messages as fresh.
        try await backend.refresh(folder: Self.inboxFolder)
        #expect(await backend.signInTrustAssessment(for: "INBOX:101") == .unavailable(.notFreshDelivery))

        // New arrival on subsequent refresh passes Authentication-Results verification.
        listingBox.set([
            Self.makeListing(uid: 102, date: clock.now),
            Self.makeListing(uid: 101, date: clock.now.addingTimeInterval(-3600))
        ], for: "INBOX")
        try await backend.refresh(folder: Self.inboxFolder)

        let assessment = await backend.signInTrustAssessment(for: "INBOX:102")
        #expect(assessment == .pass(fromDomain: "bank.example"))
        #expect(callLog.fetchedSections == ["HEADER"])
        #expect(callLog.fetchedBodies.isEmpty)

        // Disconnect clears live fresh-delivery provenance.
        await backend.disconnect()
        #expect(await backend.signInTrustAssessment(for: "INBOX:102") == .unavailable(.notFreshDelivery))
    }

    @Test("IMAPSMTPBackend rejects non-inbox, stale, and spoofed Authentication-Results deliveries")
    func imapRejectsWrongFolderStaleAndSpoofed() async throws {
        let clock = MutableClock()
        let listingBox = ListingBox()
        let rawHeadersByUID: [Int: String] = [
            201: """
            Authentication-Results: mx.fastmail.example; dmarc=fail header.from=bank.example; dkim=fail\r
            Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example\r
            From: alerts@bank.example\r
            \r
            """,
            202: """
            Authentication-Results: mx.fastmail.example; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
            From: alerts@bank.example\r
            \r
            """,
            301: """
            Authentication-Results: mx.fastmail.example; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
            From: alerts@bank.example\r
            \r
            """
        ]

        listingBox.set([Self.makeListing(uid: 100, date: clock.now.addingTimeInterval(-7200))], for: "INBOX")
        listingBox.set([Self.makeListing(uid: 300, date: clock.now.addingTimeInterval(-7200))], for: "Junk")

        let backend = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.testConfig,
            credential: Self.testCredential,
            listFolders: { _, _ in
                [Self.inboxListing, Self.junkListing]
            },
            listMessages: { _, _, folderID, _, _ in
                IMAPMessageListingPage(messages: listingBox.listings(for: folderID))
            },
            fetchMessagePart: { _, _, _, uid, _, _ in
                Data((rawHeadersByUID[uid] ?? "").utf8)
            },
            signInTrustNow: { clock.now }
        )

        try await backend.connect()
        try await backend.refresh(folder: Self.inboxFolder)
        try await backend.refresh(folder: Self.spamFolder)

        listingBox.set([
            Self.makeListing(uid: 201, date: clock.now),
            Self.makeListing(uid: 202, date: clock.now.addingTimeInterval(-601)),
            Self.makeListing(uid: 100, date: clock.now.addingTimeInterval(-7200))
        ], for: "INBOX")
        listingBox.set([
            Self.makeListing(uid: 301, date: clock.now),
            Self.makeListing(uid: 300, date: clock.now.addingTimeInterval(-7200))
        ], for: "Junk")
        try await backend.refresh(folder: Self.inboxFolder)
        try await backend.refresh(folder: Self.spamFolder)

        #expect(await backend.signInTrustAssessment(for: "INBOX:201") == .unavailable(.dmarcNotPass))
        #expect(await backend.signInTrustAssessment(for: "INBOX:202") == .unavailable(.stale))
        #expect(await backend.signInTrustAssessment(for: "Junk:301") == .unavailable(.wrongFolder))
    }

    @Test("IMAPSMTPBackend re-verifies delivered notification after restart using cached header date and raw headers")
    func imapDeliveredNotificationReassessment() async throws {
        let clock = MutableClock()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let validHeaders = """
        Authentication-Results: mx.icloud.example; spf=pass smtp.mailfrom=bounce@bank.example; dmarc=pass header.from=bank.example\r
        From: Bank <alerts@bank.example>\r
        \r
        """
        let backend = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.testConfig,
            credential: Self.testCredential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [Self.makeListing(uid: 501, date: clock.now)])
            },
            fetchMessagePart: { _, _, _, _, _, _ in Data(validHeaders.utf8) },
            headerCache: headerCache,
            signInTrustNow: { clock.now }
        )

        try await backend.connect()
        try await backend.refresh(folder: Self.inboxFolder)

        // Live assessment fails because UID 501 was in the initial listing (not a live delta).
        #expect(await backend.signInTrustAssessment(for: "INBOX:501") == .unavailable(.notFreshDelivery))
        // Delivered-notification re-assessment still passes while inside the 10-minute window.
        #expect(
            await backend.signInTrustAssessmentForDeliveredNotification(for: "INBOX:501")
                == .pass(fromDomain: "bank.example")
        )

        // Once 10 minutes elapse, delivered-notification re-assessment also fails closed.
        clock.now = clock.now.addingTimeInterval(601)
        #expect(
            await backend.signInTrustAssessmentForDeliveredNotification(for: "INBOX:501")
                == .unavailable(.stale)
        )
    }
}
