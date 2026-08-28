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

@Suite("Mailbox action source scope policy")
struct MailboxActionSourceScopePolicyTests {
    private let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")

    @Test("builds labeled scope from the selected source section")
    func buildsLabeledScopeFromSelectedSourceSection() {
        let scope = MailboxActionSourceScopePolicy.make(
            sourceID: sourceID,
            section: Self.section(sourceID: sourceID)
        )

        #expect(scope.sourceID == sourceID)
        #expect(scope.accountName == "Work")
        #expect(scope.mailboxName == "Primary")
        #expect(scope.mailboxAddress == "me@example.com")
    }

    @Test("preserves source id when section metadata is unavailable")
    func preservesSourceIDWhenSectionMetadataIsUnavailable() {
        let scope = MailboxActionSourceScopePolicy.make(sourceID: sourceID, section: nil)

        #expect(scope.sourceID == sourceID)
        #expect(scope.accountName == nil)
        #expect(scope.mailboxName == nil)
        #expect(scope.mailboxAddress == nil)
    }

    private static func section(sourceID: MailSourceID) -> MailSourceSection {
        MailSourceSection(
            id: sourceID,
            account: BrevAccount(
                id: sourceID.accountID,
                displayName: "Work",
                emailAddress: "me@example.com"
            ),
            mailbox: Mailbox(
                id: sourceID.mailboxID,
                email: "me@example.com",
                displayName: "Primary"
            ),
            folders: [Folder(id: "inbox", name: "Inbox", role: .inbox)]
        )
    }
}
