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

@Suite("MessageDeletionOperation")
struct MessageDeletionOperationTests {
    @Test("delete operation delegates trash semantics to the backend")
    func deleteOperationDelegatesTrashSemanticsToBackend() {
        #expect(MessageDeletionOperation
            .operation(for: Self.makeHeader(id: "inbox-1", folderID: "inbox")) == .delete(messageIDs: ["inbox-1"]))
        #expect(MessageDeletionOperation
            .operation(for: Self.makeHeader(id: "trash-1", folderID: "trash")) == .delete(messageIDs: ["trash-1"]))
    }

    private static func makeHeader(
        id: MessageHeader.ID,
        folderID: Folder.ID
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
