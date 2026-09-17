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

@MainActor
struct MailRootResponseSourceTests {
    let first = MailSourceID(accountID: "first", mailboxID: "primary")
    let second = MailSourceID(accountID: "second", mailboxID: "primary")

    @Test("folder and mailbox replies cannot overwrite a newly selected account")
    func loadsStayInTheirSource() {
        let folder = MailRootFolderLoadRequest(id: 1, sourceID: first)
        let mailbox = MailRootMailboxLoadRequest(id: 1, sourceID: first)
        #expect(!MailRootFolderLoadResponsePolicy.canApplyResponse(
            request: folder,
            activeRequest: folder,
            currentSourceID: second
        ))
        #expect(!MailRootMailboxLoadResponsePolicy.canApplyResponse(
            request: mailbox,
            activeRequest: mailbox,
            currentSourceID: second
        ))
        #expect(MailRootFolderLoadResponsePolicy.canApplyResponse(request: folder, activeRequest: folder, currentSourceID: first))
    }

    @Test("matching raw folder IDs do not allow a command response into another account")
    func commandsStayInTheirSource() {
        let request = MailRootCommandMutationRequest(id: 1, sourceFolderID: "inbox", sourceID: first)
        #expect(!MailRootCommandMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "inbox",
            currentSourceID: second
        ))
        #expect(MailRootCommandMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "inbox",
            currentSourceID: first
        ))
    }

    @Test("an optimistic update cannot overwrite another account's colliding reader header")
    func optimisticUpdatesStayInTheirSource() {
        let header = MessageHeader(
            id: "same",
            threadID: "thread",
            folderID: "inbox",
            from: Correspondent(email: "first@example.com"),
            subject: "First account",
            snippet: "",
            date: Date()
        )
        let navigation = MailNavigationState(
            selectedSourceID: first,
            selectedMessageID: header.id,
            currentFolderHeaders: [header]
        )
        navigation.updateHeader(id: header.id, sourceID: second) { $0.isRead = !header.isRead }
        #expect(navigation.selectedHeader == header)
    }
}
