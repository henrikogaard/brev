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

@Suite("MessageOpenReadRollback")
@MainActor
struct MessageOpenReadRollbackTests {
    @Test("rollback restores the original read state")
    func rollbackRestoresOriginalReadState() {
        let header = Self.makeHeader(isRead: false)
        let navigation = MailNavigationState(
            currentFolderHeaders: [header]
        )
        let rollback = MessageOpenReadRollback(header: header)

        navigation.updateHeader(id: header.id) { $0.isRead = true }
        rollback.restore(navigation: navigation)

        #expect(navigation.currentFolderHeaders.first?.isRead == false)
    }

    private static func makeHeader(isRead: Bool) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: isRead
        )
    }
}
