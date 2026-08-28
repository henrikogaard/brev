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

@Suite("MessageCommandMutationRollback")
@MainActor
struct MessageCommandMutationRollbackTests {
    @Test("rollback restores root navigation after failed command mutation")
    func rollbackRestoresRootNavigationAfterFailedCommandMutation() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let navigation = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second],
            bulkSelection: [first.id]
        )
        let rollback = MessageCommandMutationRollback(navigation: navigation)

        navigation.removeHeaders(ids: [second.id])
        navigation.bulkSelection.removeAll()
        rollback.restore(navigation: navigation)

        #expect(navigation.currentFolderHeaders == [first, second])
        #expect(navigation.selectedMessageID == second.id)
        #expect(navigation.bulkSelection == [first.id])
    }

    private static func makeHeader(id: MessageHeader.ID) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            to: [Correspondent(name: "Brev", email: "hello@brev.test")],
            subject: "Subject \(id)",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }
}
