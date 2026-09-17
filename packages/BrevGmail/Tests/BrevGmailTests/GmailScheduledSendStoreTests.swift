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
@testable import BrevGmail
import Foundation
import Testing

@Suite("Durable Gmail scheduling")
struct GmailScheduledSendStoreTests {
    @Test("delivery refreshes only the Date header while preserving message identity and MIME content")
    func deliveryDatePreservesContent() throws {
        let original = "From: sender@example.org\r\nDate: Yesterday\r\nMessage-ID: <stable@example.org>\r\n\r\nBody\r\nDate: keep this body line\r\n"
        let result = try GmailScheduledMIME.source(Data(original.utf8), sentAt: Date(timeIntervalSince1970: 0))
        #expect(result.contains("Date: Thu, 01 Jan 1970 00:00:00 +0000\r\n"))
        #expect(result.contains("Message-ID: <stable@example.org>\r\n"))
        #expect(result.hasSuffix("\r\n\r\nBody\r\nDate: keep this body line\r\n"))
    }

    @Test("claim ownership and interrupted delivery survive competing database connections")
    func claimsAreExclusiveAndRecoverable() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-queue-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try SQLiteGmailAccountStore(databaseURL: url)
        try await first.replaceSnapshot(GmailAccountSnapshot(
            accountID: "a",
            state: .init(accountID: "a", emailAddress: "a@example.org"),
            labels: [],
            messages: []
        ))
        let draft = Draft(id: "queued", subject: "Frozen", scheduledFor: Date(timeIntervalSince1970: 1000))
        try await first.setDraft(draft, accountID: "a")
        try await first.enqueueScheduledSend(draft, rawMIME: Data("Subject: Frozen\r\n\r\nBody".utf8), accountID: "a")
        #expect(try await first
            .claimScheduledSend(accountID: "a", draftID: draft.id, now: Date(timeIntervalSince1970: 500)) == nil)
        let second = try SQLiteGmailAccountStore(databaseURL: url)
        async let one = first.claimScheduledSend(accountID: "a", draftID: draft.id, now: Date(timeIntervalSince1970: 2000))
        async let two = second.claimScheduledSend(accountID: "a", draftID: draft.id, now: Date(timeIntervalSince1970: 2000))
        let pair = try await (one, two)
        let attempts = [pair.0, pair.1].compactMap { $0 }
        #expect(attempts.count == 1)
        let original = try #require(attempts.first)
        try await second.recoverInterruptedScheduledSends(accountID: "a")
        #expect(try await first.scheduledSends(accountID: "a").first?.state == .needsReview)
        #expect(try await first
            .claimScheduledSend(accountID: "a", draftID: draft.id, now: Date(timeIntervalSince1970: 3000)) == nil)
        try await second.rescheduleSend(
            accountID: "a",
            draftID: draft.id,
            date: Date(timeIntervalSince1970: 1000),
            allowReview: true
        )
        let fresh = try #require(try await second.claimScheduledSend(
            accountID: "a",
            draftID: draft.id,
            now: Date(timeIntervalSince1970: 3000)
        ))
        #expect(fresh.attemptID != original.attemptID)
        #expect(try await first.completeScheduledSend(accountID: "a", draftID: draft.id, attemptID: original.attemptID) == false)
        #expect(try await second.scheduledSends(accountID: "a").first?.state == .delivering)
        _ = try await second.completeScheduledSend(accountID: "a", draftID: draft.id, attemptID: fresh.attemptID)
        #expect(try await first.scheduledSends(accountID: "a").isEmpty)
    }

    @Test("retry delay respects provider limits and never guesses that uncertain delivery failed")
    func retryClassification() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(GmailScheduledRetryPolicy.retryDate(for: GmailAPIError.missingAccessToken, attempt: 10, now: now) == nil)
        #expect(GmailScheduledRetryPolicy.retryDate(
            for: GmailAPIError.retryable(statusCode: 429, retryAfter: 600),
            attempt: 1,
            now: now
        )
            == Date(timeIntervalSince1970: 1600))
        #expect(GmailScheduledRetryPolicy.retryDate(for: GmailAPIError.missingAccessToken, attempt: 3, now: now)
            == Date(timeIntervalSince1970: 1240))
        #expect(GmailScheduledRetryPolicy.retryDate(for: GmailAPIError.ambiguousSendOutcome, attempt: 1, now: now) == nil)
        #expect(GmailScheduledRetryPolicy.retryDate(for: GmailAPIError.transportFailure, attempt: 1, now: now) == nil)
        #expect(GmailScheduledRetryPolicy.retryDate(
            for: GmailAPIError.retryable(statusCode: 503, retryAfter: nil),
            attempt: 1,
            now: now
        ) == nil)
    }
}
