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
import Testing

@Suite("MailRootFolderNamePolicy")
struct MailRootFolderNamePolicyTests {
    @Test("background account never falls back to selected account folders")
    func backgroundAccountDoesNotUseSelectedAccountFolderName() {
        let sections = [Self.section(accountID: "background", folderName: "Background Inbox")]

        #expect(MailRootFolderNamePolicy.resolve(
            folderID: "inbox",
            backendAccountID: "background",
            selectedAccountID: "selected",
            selectedAccountFolders: [Folder(id: "inbox", name: "Selected Inbox", role: .inbox)],
            sourceSections: sections
        ) == "Background Inbox")

        #expect(MailRootFolderNamePolicy.resolve(
            folderID: "missing",
            backendAccountID: "background",
            selectedAccountID: "selected",
            selectedAccountFolders: [Folder(id: "missing", name: "Selected Only", role: .custom)],
            sourceSections: sections
        ) == nil)
    }

    @Test("selected account keeps global folder fallback")
    func selectedAccountUsesGlobalFolderFallback() {
        #expect(MailRootFolderNamePolicy.resolve(
            folderID: "inbox",
            backendAccountID: "selected",
            selectedAccountID: "selected",
            selectedAccountFolders: [Folder(id: "inbox", name: "Selected Inbox", role: .inbox)],
            sourceSections: []
        ) == "Selected Inbox")
    }

    @Test("source section name wins over selected account fallback")
    func sourceSectionNameWinsOverSelectedAccountFallback() {
        #expect(MailRootFolderNamePolicy.resolve(
            folderID: "inbox",
            backendAccountID: "selected",
            selectedAccountID: "selected",
            selectedAccountFolders: [Folder(id: "inbox", name: "Stale Inbox", role: .inbox)],
            sourceSections: [Self.section(accountID: "selected", folderName: "Fresh Inbox")]
        ) == "Fresh Inbox")
    }

    private static func section(accountID: String, folderName: String) -> MailSourceSection {
        let account = BrevAccount(
            id: accountID,
            displayName: accountID,
            emailAddress: "\(accountID)@example.com"
        )
        let sourceID = MailSourceID(accountID: accountID, mailboxID: "primary")
        return MailSourceSection(
            id: sourceID,
            account: account,
            mailbox: Mailbox(id: "primary", email: account.emailAddress, displayName: "Primary"),
            folders: [Folder(id: "inbox", name: folderName, role: .inbox)]
        )
    }
}
