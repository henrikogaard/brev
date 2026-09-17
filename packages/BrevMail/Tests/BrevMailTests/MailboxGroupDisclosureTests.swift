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

@Suite("Independent mailbox groups")
struct MailboxGroupDisclosureTests {
    @Test("saved expansion keeps multiple mailboxes open across profile changes")
    func restoresMultipleGroups() throws {
        let work = MailSourceID(accountID: "account", mailboxID: "work")
        let personal = MailSourceID(accountID: "account", mailboxID: "personal")
        let data = try JSONEncoder().encode(Set([work, personal]))
        let restored = FolderSidebarSourceExpansionPolicy.restoredExpandedSourceIDs(
            from: data, sourceIDs: [work], selectedSourceID: work
        )
        #expect(restored == [work, personal])
        #expect(FolderSidebarSourceExpansionPolicy.toggling(work, in: restored) == [personal])
    }

    @Test("an intentionally collapsed sidebar stays collapsed when restored")
    func restoresEmptyExpansion() throws {
        let work = MailSourceID(accountID: "account", mailboxID: "work")
        let data = try JSONEncoder().encode(Set<MailSourceID>())
        #expect(FolderSidebarSourceExpansionPolicy.restoredExpandedSourceIDs(
            from: data, sourceIDs: [work], selectedSourceID: work
        ).isEmpty)
    }

    @Test("first use reveals the selected mailbox without expanding every account")
    func initialSelection() {
        let work = MailSourceID(accountID: "account", mailboxID: "work")
        let personal = MailSourceID(accountID: "account", mailboxID: "personal")
        #expect(FolderSidebarSourceExpansionPolicy.restoredExpandedSourceIDs(
            from: Data(), sourceIDs: [personal, work], selectedSourceID: work
        ) == [work])
    }
}
