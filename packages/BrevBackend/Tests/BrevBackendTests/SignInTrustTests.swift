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
        private var sourceFetches: [Int] = []
        private var idleFolders: [Folder.ID] = []

        func recordSection(_ section: String) {
            lock.withLock { sections.append(section) }
        }

        func recordBodyFetch(_ uid: Int) {
            lock.withLock { bodyFetches.append(uid) }
        }

        func recordSourceFetch(_ uid: Int) {
            lock.withLock { sourceFetches.append(uid) }
        }

        func recordIdleFolder(_ folderID: Folder.ID) {
            lock.withLock { idleFolders.append(folderID) }
        }

        var fetchedSections: [String] { lock.withLock { sections } }
        var fetchedBodies: [Int] { lock.withLock { bodyFetches } }
        var fetchedSources: [Int] { lock.withLock { sourceFetches } }
        var watchedIdleFolders: [Folder.ID] { lock.withLock { idleFolders } }
    }

    private static let testAccount = BrevAccount(
        id: BrevAccount.imapSMTPAccountID(forEmailAddress: "user@fastmail.com"),
        displayName: "Fastmail",
        emailAddress: "user@fastmail.com"
    )

    private static func makeConfig(imapHost: String = "imap.fastmail.com") -> IMAPAccountConfiguration {
        IMAPAccountConfiguration(
            accountID: testAccount.id,
            emailAddress: testAccount.emailAddress,
            displayName: testAccount.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: imapHost,
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.fastmail.com",
                port: 465,
                tlsMode: .implicit,
                authentication: .password
            ),
            credentialID: testAccount.id
        )
    }

    private static let testCredential = MailAccountCredential(
        incomingUsername: "user@fastmail.com",
        outgoingUsername: "user@fastmail.com",
        secret: "app-password",
        authentication: .password
    )

    private static let inboxFolder = Folder(id: "INBOX", name: "Inbox", role: .inbox)
    private static let sentFolder = Folder(id: "Sent", name: "Sent", role: .sent)
    private static let spamFolder = Folder(id: "Junk", name: "Junk", role: .spam)

    private static func makeListing(
        uid: Int,
        date: Date,
        internalDate: Date? = nil,
        from: String = "alerts@bank.example"
    ) -> IMAPMessageListing {
        IMAPMessageListing(
            uid: uid,
            messageID: "<msg-\(uid)@bank.example>",
            subject: "Sign-in code",
            from: Correspondent(name: "Bank", email: from),
            to: [Correspondent(email: testAccount.emailAddress)],
            cc: [],
            bcc: [],
            date: date,
            internalDate: internalDate,
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

    private static let sentListing = IMAPFolderListing(
        path: "Sent",
        displayName: "Sent",
        delimiter: "/",
        flags: ["\\Sent"],
        role: .sent
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

    @Test("capability requires listing, header-only part fetch, and non-local receiver provenance")
    func capabilityReporting() {
        #expect(BackendExtendedCapabilities.trustedSignInAssessment.rawValue == 1 << 17)
        let localBackend = LocalMailBackend()
        #expect(!localBackend.extendedCapabilities.contains(.trustedSignInAssessment))

        let minimalIMAP = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.makeConfig(),
            credential: Self.testCredential,
            listFolders: { _, _ in [] }
        )
        #expect(!minimalIMAP.extendedCapabilities.contains(.trustedSignInAssessment))

        // Source-only backend (BODY.PEEK[] without header-only BODY.PEEK[HEADER]) must NOT advertise it.
        let sourceOnlyIMAP = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.makeConfig(),
            credential: Self.testCredential,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            fetchMessageSource: { _, _, _, uid in IMAPMessageSource(uid: uid, rawMessage: "") }
        )
        #expect(!sourceOnlyIMAP.extendedCapabilities.contains(.trustedSignInAssessment))

        // Loopback IMAP host (e.g. local bridge without explicit trusted authserv-id) must NOT advertise it.
        for localHost in ["127.0.0.1", "localhost", "mail.local"] {
            let localHostIMAP = IMAPSMTPBackend(
                account: Self.testAccount,
                configuration: Self.makeConfig(imapHost: localHost),
                credential: Self.testCredential,
                listFolders: { _, _ in [] },
                listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
                fetchMessagePart: { _, _, _, _, _, _ in Data() }
            )
            #expect(!localHostIMAP.extendedCapabilities.contains(.trustedSignInAssessment))
        }

        let partBackedIMAP = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.makeConfig(imapHost: "imap.fastmail.com"),
            credential: Self.testCredential,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            fetchMessagePart: { _, _, _, _, _, _ in Data() }
        )
        #expect(partBackedIMAP.extendedCapabilities.contains(.trustedSignInAssessment))
    }

    @Test("IMAPMessageListing parses server INTERNALDATE while preserving ENVELOPE Date header for display")
    func listingParsesInternalDateSeparatelyFromEnvelopeDate() throws {
        let fetchLine = "* 1 FETCH (UID 42 FLAGS (\\Seen) INTERNALDATE \"24-Nov-2026 14:30:00 +0000\" "
            + "ENVELOPE (\"Tue, 24 Nov 2026 14:19:00 +0000\" \"Sign-in code\" "
            + "((\"Bank\" NIL \"alerts\" \"bank.example\")) NIL NIL "
            + "((NIL NIL \"user\" \"fastmail.com\")) NIL NIL NIL \"<msg-42@bank.example>\"))"
        let listing = try #require(IMAPMessageListing.parse(fetchLine))
        let internalDate = try #require(listing.internalDate)
        #expect(Int(internalDate.timeIntervalSince(listing.date)) == 660)
    }

    @Test("IMAPSMTPBackend uses INTERNALDATE for 10-minute freshness window and never falls back to BODY.PEEK[]")
    func imapFreshnessUsesInternalDateAndFailsClosedOnHeaderFetchFailure() async throws {
        let clock = MutableClock()
        let listingBox = ListingBox()
        let callLog = CallLog()
        let validHeaders = """
        Authentication-Results: mx2.messagingengine.com;\r
            dkim=pass header.d=bank.example;\r
            dmarc=pass header.from=bank.example\r
        From: Bank <alerts@bank.example>\r
        Subject: Code\r
        \r
        """

        listingBox.set(
            [Self.makeListing(
                uid: 101,
                date: clock.now.addingTimeInterval(-3600),
                internalDate: clock.now.addingTimeInterval(-3600)
            )],
            for: "INBOX"
        )

        let backend = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.makeConfig(imapHost: "imap.fastmail.com"),
            credential: Self.testCredential,
            listFolders: { _, _ in [Self.inboxListing, Self.junkListing] },
            listMessages: { _, _, folderID, _, _ in
                IMAPMessageListingPage(messages: listingBox.listings(for: folderID))
            },
            fetchMessageSource: { _, _, _, uid in
                callLog.recordSourceFetch(uid)
                return IMAPMessageSource(uid: uid, rawMessage: validHeaders + "Your code is 123456")
            },
            fetchMessageBody: { _, _, _, uid in
                callLog.recordBodyFetch(uid)
                return MessageBody(messageID: "INBOX:\(uid)", plainText: "Code 123456")
            },
            fetchMessagePart: { _, _, _, uid, section, _ in
                callLog.recordSection(section)
                if uid == 104 {
                    throw IMAPClientError.transport("header fetch failed")
                }
                return Data(validHeaders.utf8)
            },
            signInTrustNow: { clock.now }
        )

        try await backend.connect()
        try await backend.refresh(folder: Self.inboxFolder)
        #expect(await backend.signInTrustAssessment(for: "INBOX:101") == .unavailable(.notFreshDelivery))

        // UID 102: composed 11 minutes ago (old Date:) but received 30 seconds ago (INTERNALDATE) -> PASSES.
        // UID 103: Date: is now, but received 11 minutes ago (INTERNALDATE) -> STALE.
        // UID 104: header fetch throws -> fails closed without ever falling back to fetchMessageSource (BODY.PEEK[]).
        listingBox.set([
            Self.makeListing(uid: 102, date: clock.now.addingTimeInterval(-660), internalDate: clock.now.addingTimeInterval(-30)),
            Self.makeListing(uid: 103, date: clock.now, internalDate: clock.now.addingTimeInterval(-660)),
            Self.makeListing(uid: 104, date: clock.now, internalDate: clock.now.addingTimeInterval(-10)),
            Self.makeListing(
                uid: 101,
                date: clock.now.addingTimeInterval(-3600),
                internalDate: clock.now.addingTimeInterval(-3600)
            )
        ], for: "INBOX")
        try await backend.refresh(folder: Self.inboxFolder)

        #expect(await backend.signInTrustAssessment(for: "INBOX:102") == .pass(fromDomain: "bank.example"))
        #expect(await backend.signInTrustAssessment(for: "INBOX:103") == .unavailable(.stale))
        #expect(await backend.signInTrustAssessment(for: "INBOX:104") == .unavailable(.noTrustedHeader))
        #expect(callLog.fetchedSections == ["HEADER", "HEADER"])
        #expect(callLog.fetchedSources.isEmpty)
        #expect(callLog.fetchedBodies.isEmpty)

        // Disconnect clears live fresh-delivery provenance.
        await backend.disconnect()
        #expect(await backend.signInTrustAssessment(for: "INBOX:102") == .unavailable(.notFreshDelivery))
    }

    @Test("IMAPSMTPBackend rejects non-inbox, foreign authserv-id, and spoofed Authentication-Results deliveries")
    func imapRejectsWrongFolderForeignAndSpoofed() async throws {
        let clock = MutableClock()
        let listingBox = ListingBox()
        let rawHeadersByUID: [Int: String] = [
            201: """
            Authentication-Results: mx2.messagingengine.com; dmarc=fail header.from=bank.example; dkim=fail\r
            Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example\r
            From: alerts@bank.example\r
            \r
            """,
            202: """
            Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example\r
            From: alerts@bank.example\r
            \r
            """,
            301: """
            Authentication-Results: mx2.messagingengine.com; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
            From: alerts@bank.example\r
            \r
            """
        ]

        listingBox.set(
            [Self.makeListing(
                uid: 100,
                date: clock.now.addingTimeInterval(-7200),
                internalDate: clock.now.addingTimeInterval(-7200)
            )],
            for: "INBOX"
        )
        listingBox.set(
            [Self.makeListing(
                uid: 300,
                date: clock.now.addingTimeInterval(-7200),
                internalDate: clock.now.addingTimeInterval(-7200)
            )],
            for: "Junk"
        )

        let backend = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.makeConfig(imapHost: "imap.fastmail.com"),
            credential: Self.testCredential,
            listFolders: { _, _ in [Self.inboxListing, Self.junkListing] },
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
            Self.makeListing(uid: 201, date: clock.now, internalDate: clock.now),
            Self.makeListing(uid: 202, date: clock.now, internalDate: clock.now),
            Self.makeListing(
                uid: 100,
                date: clock.now.addingTimeInterval(-7200),
                internalDate: clock.now.addingTimeInterval(-7200)
            )
        ], for: "INBOX")
        listingBox.set([
            Self.makeListing(uid: 301, date: clock.now, internalDate: clock.now),
            Self.makeListing(
                uid: 300,
                date: clock.now.addingTimeInterval(-7200),
                internalDate: clock.now.addingTimeInterval(-7200)
            )
        ], for: "Junk")
        try await backend.refresh(folder: Self.inboxFolder)
        try await backend.refresh(folder: Self.spamFolder)

        #expect(await backend.signInTrustAssessment(for: "INBOX:201") == .unavailable(.dmarcNotPass))
        #expect(await backend.signInTrustAssessment(for: "INBOX:202") == .unavailable(.noTrustedHeader))
        #expect(await backend.signInTrustAssessment(for: "Junk:301") == .unavailable(.wrongFolder))
    }

    @Test("cold delivered-notification reassessment awaits in-flight remote connection on cache-restored backend")
    func coldDeliveredNotificationAwaitsRemoteReconnect() async throws {
        let clock = MutableClock()
        let folderCache = InMemoryIMAPFolderSnapshotCache()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        await folderCache.setSnapshot(
            IMAPFolderCacheSnapshot(folders: [Self.inboxFolder], folderDelimitersByID: ["INBOX": "/"]),
            accountID: Self.testAccount.id
        )
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [
                MessageHeader(
                    id: "INBOX:501",
                    threadID: "<msg-501@bank.example>",
                    folderID: "INBOX",
                    from: Correspondent(name: "Bank", email: "alerts@bank.example"),
                    subject: "Code",
                    snippet: "",
                    date: clock.now.addingTimeInterval(-700),
                    internalDate: clock.now.addingTimeInterval(-30)
                )
            ]),
            accountID: Self.testAccount.id,
            folderID: "INBOX"
        )

        let validHeaders = """
        Authentication-Results: b.mail.icloud.com; spf=pass smtp.mailfrom=bounce@bank.example; dmarc=pass header.from=bank.example\r
        From: Bank <alerts@bank.example>\r
        \r
        """
        let backend = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.makeConfig(imapHost: "imap.mail.me.com"),
            credential: Self.testCredential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            fetchMessagePart: { _, _, _, _, _, _ in Data(validHeaders.utf8) },
            folderCache: folderCache,
            headerCache: headerCache,
            signInTrustNow: { clock.now },
            signInTrustReconnectTimeout: 1.0
        )

        // Simulate cache-first startup while remote connect is still in flight.
        #expect(await backend.restoreCachedFoldersForStartup())
        let reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            try? await backend.connect()
        }
        let assessment = await backend.signInTrustAssessmentForDeliveredNotification(for: "INBOX:501")
        await reconnectTask.value
        #expect(assessment == .pass(fromDomain: "bank.example"))

        // Once 10 minutes elapse past INTERNALDATE, reassessment fails closed.
        clock.now = clock.now.addingTimeInterval(601)
        #expect(
            await backend.signInTrustAssessmentForDeliveredNotification(for: "INBOX:501")
                == .unavailable(.stale)
        )
    }

    @Test("focusInboxForBackgroundSubscription redirects IDLE to INBOX after closing a Sent view")
    func backgroundSubscriptionWatchesInboxAfterSent() async throws {
        let callLog = CallLog()
        let backend = IMAPSMTPBackend(
            account: Self.testAccount,
            configuration: Self.makeConfig(imapHost: "imap.fastmail.com"),
            credential: Self.testCredential,
            listFolders: { _, _ in [Self.inboxListing, Self.sentListing] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            fetchMessagePart: { _, _, _, _, _, _ in Data() },
            idleEvents: { _, _, folderID in
                callLog.recordIdleFolder(folderID)
                return AsyncThrowingStream { continuation in
                    continuation.onTermination = { _ in }
                }
            }
        )

        try await backend.connect()
        // Viewing Sent makes Sent the active folder for IDLE.
        _ = try await backend.messages(in: Self.sentFolder, pageToken: nil)

        // Closing the last window refocuses background subscription back to INBOX.
        await backend.focusInboxForBackgroundSubscription()
        let stream = backend.subscribeToChanges()
        let reader = Task {
            for await _ in stream {
                break
            }
        }
        for _ in 0 ..< 50 where callLog.watchedIdleFolders.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        reader.cancel()
        await reader.value

        #expect(callLog.watchedIdleFolders == ["INBOX"])
    }
}
