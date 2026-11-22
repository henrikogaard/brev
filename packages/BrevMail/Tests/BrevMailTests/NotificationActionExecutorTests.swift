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

@Suite("NotificationActionExecutor")
@MainActor
struct NotificationActionExecutorTests {
    @Test("markRead updates the targeted account without a view")
    func markReadUpdatesTargetedAccount() async throws {
        let backend = MockBackend(account: BrevAccount(
            id: "acct-1",
            displayName: "Personal",
            emailAddress: "henrik@example.com"
        ))
        try await backend.connect()
        let inbox = try #require(try await backend.folders().first { $0.role == .inbox })
        let page = try await backend.messages(in: inbox, pageToken: nil)
        let unreadMessage = try #require(page.headers.first { !$0.isRead })

        var mutatedRoutes: [NotificationMailRoute] = []
        let executor = NotificationActionExecutor(
            backendsProvider: { [backend] },
            onMutated: { mutatedRoutes.append($0) }
        )

        let route = NotificationMailRoute(
            accountID: "acct-1",
            folderID: inbox.id,
            messageID: unreadMessage.id
        )
        let didMutate = await executor.markRead(route: route)

        #expect(didMutate)
        #expect(mutatedRoutes == [route])
        let updated = try await backend.messages(in: inbox, pageToken: nil).headers
            .first { $0.id == unreadMessage.id }
        #expect(updated?.isRead == true)
    }

    @Test("archive moves the targeted message to the account's archive folder")
    func archiveMovesTargetedMessage() async throws {
        let backend = MockBackend(account: BrevAccount(
            id: "acct-1",
            displayName: "Personal",
            emailAddress: "henrik@example.com"
        ))
        try await backend.connect()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let archive = try #require(folders.first { $0.role == .archive })
        let message = try #require(try await backend.messages(in: inbox, pageToken: nil).headers.first)

        let executor = NotificationActionExecutor(backendsProvider: { [backend] })
        let route = NotificationMailRoute(
            accountID: "acct-1",
            folderID: inbox.id,
            messageID: message.id
        )
        let didMutate = await executor.archive(route: route)

        #expect(didMutate)
        let archivedIDs = try await backend.messages(in: archive, pageToken: nil).headers.map(\.id)
        #expect(archivedIDs.contains(message.id))
    }

    @Test("actions fail closed when the route targets an unconnected account")
    func actionsFailClosedForUnknownAccount() async throws {
        let backend = MockBackend(account: BrevAccount(
            id: "acct-1",
            displayName: "Personal",
            emailAddress: "henrik@example.com"
        ))
        try await backend.connect()
        let inbox = try #require(try await backend.folders().first { $0.role == .inbox })
        let unreadMessage = try #require(
            try await backend.messages(in: inbox, pageToken: nil).headers.first { !$0.isRead }
        )

        let executor = NotificationActionExecutor(backendsProvider: { [backend] })
        let foreignRoute = NotificationMailRoute(
            accountID: "acct-other",
            folderID: inbox.id,
            messageID: unreadMessage.id
        )

        #expect(await executor.markRead(route: foreignRoute) == false)
        #expect(await executor.archive(route: foreignRoute) == false)
        let stillUnread = try await backend.messages(in: inbox, pageToken: nil).headers
            .first { $0.id == unreadMessage.id }
        #expect(stillUnread?.isRead == false)
    }
}
