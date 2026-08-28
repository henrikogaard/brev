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

@Suite("ComposeQuotedBodyUpgradePolicy")
struct ComposeQuotedBodyUpgradePolicyTests {
    @Test("reply and forward start pending until upgrade completes")
    func replyAndForwardStartPending() {
        #expect(ComposeQuotedBodyUpgradePolicy.initiallyPending(
            hasRecoveredDraft: false,
            isReplyOrForward: true
        ))
        #expect(!ComposeQuotedBodyUpgradePolicy.initiallyPending(
            hasRecoveredDraft: true,
            isReplyOrForward: true
        ))
        #expect(!ComposeQuotedBodyUpgradePolicy.initiallyPending(
            hasRecoveredDraft: false,
            isReplyOrForward: false
        ))
    }

    @Test("pending upgrade blocks send and save")
    func pendingUpgradeBlocksSendAndSave() {
        #expect(ComposeQuotedBodyUpgradePolicy.blocksSending(isUpgradePending: true))
        #expect(!ComposeQuotedBodyUpgradePolicy.blocksSending(isUpgradePending: false))
    }
}
