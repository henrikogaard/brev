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

@Suite("BoundedCachedHeaderProviding")
struct BoundedCachedHeaderTests {
    private static func makeBackend(headers: [MessageHeader], folderID: String = "INBOX") async -> (
        backend: IMAPSMTPBackend,
        sourceID: MailSourceID,
        folder: Folder
    ) {
        let account = BrevAccount(
            id: "imap-bounded-test",
            displayName: "Bounded Test",
            emailAddress: "bounded@example.org"
        )
        let config = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 587,
                tlsMode: .startTLS,
                authentication: .password
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: account.emailAddress,
            outgoingUsername: account.emailAddress,
            secret: "secret",
            authentication: .password
        )
        let cache = InMemoryIMAPMailboxHeaderCache()
        await cache.setHeaders(headers, accountID: account.id, folderID: folderID)
        let backend = IMAPSMTPBackend(
            account: account,
            configuration: config,
            credential: credential,
            listFolders: { _, _ in
                Issue.record("Bounded cached header read must not connect")
                return []
            },
            headerCache: cache
        )
        let sourceID = MailSourceID(accountID: account.id, mailboxID: account.id)
        let folder = Folder(id: folderID, name: "Inbox", role: .inbox, unreadCount: 0, totalCount: headers.count)
        return (backend, sourceID, folder)
    }

    @Test("IMAPSMTPBackend exposes BoundedCachedHeaderProviding and caps results by limit and date")
    func boundedCachedHeadersRespectsLimitAndSince() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let headers = (1 ... 40).map { index in
            MessageHeader(
                id: "INBOX:\(index)",
                threadID: "thread-\(index)",
                folderID: "INBOX",
                from: Correspondent(name: "Sender \(index)", email: "sender\(index)@example.org"),
                subject: "Subject \(index)",
                snippet: "Snippet \(index)",
                date: baseDate.addingTimeInterval(TimeInterval(index * 3600)),
                isRead: false
            )
        }
        let (backend, sourceID, folder) = await Self.makeBackend(headers: headers)

        let service = try #require(backend.extensionService(BoundedCachedHeaderProviding.self))

        let topTen = try await service.cachedMessageHeaders(in: folder, sourceID: sourceID, limit: 10)
        #expect(topTen.count == 10)
        #expect(topTen.first?.id == "INBOX:40")
        #expect(topTen.last?.id == "INBOX:31")

        let cutoff = baseDate.addingTimeInterval(TimeInterval(36 * 3600))
        let recent = try await service.cachedMessageHeaders(
            in: folder,
            sourceID: sourceID,
            limit: 50,
            since: cutoff
        )
        #expect(recent.map(\.id) == ["INBOX:40", "INBOX:39", "INBOX:38", "INBOX:37", "INBOX:36"])

        let zero = try await service.cachedMessageHeaders(in: folder, sourceID: sourceID, limit: 0)
        #expect(zero.isEmpty)
    }
}
