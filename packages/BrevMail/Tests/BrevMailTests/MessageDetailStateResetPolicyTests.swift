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

@Suite("MessageDetailStateResetPolicy")
struct MessageDetailStateResetPolicyTests {
    @Test("clearing selection resets every message-scoped field")
    func clearingSelectionResetsEveryMessageScopedField() {
        #expect(MessageDetailStateResetPolicy.clearedFields(
            for: .messageUnavailable
        ) == Set(MessageDetailTransientField.allCases))
    }

    @Test("starting a new message load clears stale content without clearing loading")
    func startingNewMessageLoadClearsStaleContentWithoutClearingLoading() {
        let fields = MessageDetailStateResetPolicy.clearedFields(for: .messageLoadStarted)

        #expect(fields.contains(.messageBody))
        #expect(fields.contains(.renderedHTML))
        #expect(fields.contains(.bodyLoadError))
        #expect(fields.contains(.downloadingAttachment))
        #expect(fields.contains(.attachmentError))
        #expect(fields.contains(.recipientsExpansion))
        #expect(fields.contains(.parsedInvite))
        #expect(fields.contains(.inviteLoadStatus))
        #expect(fields.contains(.remoteContentOverride))
        #expect(fields.contains(.calendarResponse))
        #expect(fields.contains(.inviteResponseConfirmation))
        #expect(fields.contains(.inviteResponseStatus))
        #expect(fields.contains(.failedInviteResponse))
        #expect(fields.contains(.inviteResponseProgress))
        #expect(fields.contains(.listUnsubscribeConfirmation))
        #expect(fields.contains(.quickLookPreview))
        #expect(!fields.contains(.loading))
    }

    @Test("body load failure preserves the new body error slot")
    func bodyLoadFailurePreservesNewBodyErrorSlot() {
        let fields = MessageDetailStateResetPolicy.clearedFields(for: .bodyLoadFailed)

        #expect(fields.contains(.messageBody))
        #expect(fields.contains(.renderedHTML))
        #expect(fields.contains(.attachmentError))
        #expect(fields.contains(.remoteContentOverride))
        #expect(fields.contains(.listUnsubscribeConfirmation))
        #expect(fields.contains(.quickLookPreview))
        #expect(!fields.contains(.bodyLoadError))
        #expect(!fields.contains(.loading))
    }
}
