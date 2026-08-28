/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 */

import BrevBackend
@testable import BrevMail
import Testing

@Suite("MailRootSourceLoadPresentation")
struct MailRootSourceLoadPresentationTests {
    @Test("one failed account preserves the successful account and exposes retry")
    func oneFailureDoesNotHideSuccessfulAccount() {
        let account = BrevAccount(id: "healthy", displayName: "Healthy", emailAddress: "healthy@example.org")
        let section = MailSourceSection(
            id: MailSourceID(accountID: account.id, mailboxID: "inbox"),
            account: account,
            mailbox: Mailbox(id: "inbox", email: account.emailAddress, displayName: "Inbox", isPrimary: true),
            folders: [Folder(id: "folder", name: "Inbox", role: .inbox)]
        )

        let summary = MailRootSourceLoadPresentation.summary(for: [
            .sections([section]),
            .failure(accountEmail: "failed@example.org", message: "Authentication failed")
        ])

        #expect(summary.sections == [section])
        #expect(summary.failures.count == 1)
        #expect(summary.failures.first?.accountEmail == "failed@example.org")
        #expect(summary.hasPartialFailure)

        let status = MailRootSourceLoadPresentation.partialFailureStatus(for: summary)
        #expect(status?.tone == .warning)
        #expect(status?.actionTitle == "Try Again")
        #expect(status?.message.contains("failed@example.org") == true)
    }
}
