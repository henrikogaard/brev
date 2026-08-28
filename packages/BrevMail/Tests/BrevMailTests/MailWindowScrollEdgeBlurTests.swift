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

#if os(macOS)
@testable import BrevMail
import Testing

@Suite("Scroll edge blur reduction retry")
struct MailScrollEdgeBlurRetryStateTests {
    @Test("a missing backdrop is retried a bounded number of times")
    func missingBackdropIsRetriedBoundedly() {
        var state = MailScrollEdgeBlurRetryState()

        var retries = 0
        while state.noteAttemptFailed() {
            retries += 1
            #expect(retries < MailScrollEdgeBlurRetryState.maxAttempts)
        }
        #expect(retries == MailScrollEdgeBlurRetryState.maxAttempts - 1)
        let allowedPastBudget = state.noteAttemptFailed()
        #expect(!allowedPastBudget)
    }

    @Test("a fresh reduction trigger restores the retry budget")
    func freshTriggerRestoresRetryBudget() {
        var state = MailScrollEdgeBlurRetryState()

        while state.noteAttemptFailed() {}
        let allowedWhenExhausted = state.noteAttemptFailed()
        #expect(!allowedWhenExhausted)

        state.reset()
        let allowedAfterReset = state.noteAttemptFailed()
        #expect(allowedAfterReset)
    }
}
#endif
