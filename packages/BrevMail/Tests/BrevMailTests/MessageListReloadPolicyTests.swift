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

@Suite("MessageListReloadPolicy")
struct MessageListReloadPolicyTests {
    @Test("blank search text reloads the folder")
    func blankSearchTextReloadsFolder() {
        #expect(MessageListReloadPolicy.operation(forSearchText: " \n\t ") == .folder)
    }

    @Test("nonblank search text reloads the search query")
    func nonblankSearchTextReloadsSearchQuery() {
        #expect(MessageListReloadPolicy.operation(forSearchText: "  budget \n") == .search(query: "budget"))
    }

    @Test("pending visible reload resumes when root work unblocks")
    func pendingVisibleReloadResumesWhenRootWorkUnblocks() {
        #expect(MessageListWorkResumePolicy.shouldReloadVisibleMessages(
            wasBlocked: true,
            isBlocked: false,
            hasPendingReload: true
        ))
    }

    @Test("visible reload does not resume without a pending blocked start")
    func visibleReloadDoesNotResumeWithoutPendingBlockedStart() {
        #expect(!MessageListWorkResumePolicy.shouldReloadVisibleMessages(
            wasBlocked: true,
            isBlocked: false,
            hasPendingReload: false
        ))
        #expect(!MessageListWorkResumePolicy.shouldReloadVisibleMessages(
            wasBlocked: true,
            isBlocked: true,
            hasPendingReload: true
        ))
        #expect(!MessageListWorkResumePolicy.shouldReloadVisibleMessages(
            wasBlocked: false,
            isBlocked: false,
            hasPendingReload: true
        ))
    }
}
