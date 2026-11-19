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

@testable import BrevMail
import Testing

/// When a docked reply's send or save result still applies (#302).
@Suite("Docked reply completion policy")
struct MailRootDockedReplyCompletionPolicyTests {
    @Test("a result from the open dock in the same mailbox applies")
    func current() {
        #expect(MailRootDockedReplyCompletionPolicy.isCurrent(
            completionPresentationID: 3, completionMailboxID: "work",
            dockPresentationID: 3, activeMailboxID: "work"
        ))
        #expect(MailRootDockedReplyCompletionPolicy.isCurrent(
            completionPresentationID: 3, completionMailboxID: nil,
            dockPresentationID: 3, activeMailboxID: "work"
        ))
    }

    @Test("a result after the dock closed or was replaced does not apply")
    func closedOrReplaced() {
        #expect(!MailRootDockedReplyCompletionPolicy.isCurrent(
            completionPresentationID: 3, completionMailboxID: "work",
            dockPresentationID: nil, activeMailboxID: "work"
        ))
        #expect(!MailRootDockedReplyCompletionPolicy.isCurrent(
            completionPresentationID: 3, completionMailboxID: "work",
            dockPresentationID: 4, activeMailboxID: "work"
        ))
    }

    @Test("a result after a mailbox switch does not apply")
    func mailboxSwitched() {
        #expect(!MailRootDockedReplyCompletionPolicy.isCurrent(
            completionPresentationID: 3, completionMailboxID: "work",
            dockPresentationID: 3, activeMailboxID: "personal"
        ))
    }
}
