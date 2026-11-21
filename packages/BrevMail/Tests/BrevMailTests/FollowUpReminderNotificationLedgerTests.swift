/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 - The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.
 - The Software may not be used to train, fine-tune, or evaluate AI systems
   without a separate written license from the copyright holder.
 */

@testable import BrevMail
import Foundation
import Testing

@Suite("Follow-up notification ledger")
struct FollowUpReminderNotificationLedgerTests {
    private let identifier = "brev.followUp.reminder-1"
    private let dueAt = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("repeated refreshes never requeue a fired or dismissed overdue reminder")
    func firedReminderStaysTerminal() {
        var ledger = FollowUpReminderNotificationLedger()
        let initialDecision = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(-10),
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(initialDecision)
        ledger.markScheduled(identifier: identifier, dueAt: dueAt)
        let firedDecision = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt,
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(!firedDecision)
        #expect(ledger.entries[identifier]?.state == .delivered)
        let repeatedDecision = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(3600),
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(!repeatedDecision)
    }

    @Test("persisted ledger survives restart and delivered notifications stay terminal")
    func ledgerRoundTripsAcrossRestart() throws {
        let defaultsName = "FollowUpReminderNotificationLedgerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        var ledger = FollowUpReminderNotificationLedger()
        let deliveredDecision = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(-1),
            pendingIDs: [],
            deliveredIDs: [identifier],
            authorizationAvailable: true
        )
        #expect(!deliveredDecision)
        defaults.set(try JSONEncoder().encode(ledger), forKey: FollowUpReminderNotificationLedger.userDefaultsKey)

        let data = try #require(defaults.data(forKey: FollowUpReminderNotificationLedger.userDefaultsKey))
        let restored = try JSONDecoder().decode(FollowUpReminderNotificationLedger.self, from: data)
        var afterDismissal = restored
        let dismissedDecision = afterDismissal.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(60),
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(!dismissedDecision)
    }

    @Test("a lost future pending request is restored")
    func lostFutureRequestIsRestored() {
        var ledger = FollowUpReminderNotificationLedger()
        ledger.markScheduled(identifier: identifier, dueAt: dueAt)

        let shouldRestore = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(-60),
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(shouldRestore)
    }

    @Test("a changed due date is scheduled as a new notification state")
    func changedDueDateResetsDeliveryState() {
        var ledger = FollowUpReminderNotificationLedger()
        ledger.markScheduled(identifier: identifier, dueAt: dueAt)
        let changedDueAt = dueAt.addingTimeInterval(86400)

        let shouldReschedule = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: changedDueAt,
            now: dueAt,
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(shouldReschedule)
    }

    @Test("denied permission is retried without prompting and failed scheduling stays recorded")
    func deniedAndFailedScheduling() {
        var ledger = FollowUpReminderNotificationLedger()
        let deniedDecision = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(-60),
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: false
        )
        #expect(!deniedDecision)
        let permissionGrantedDecision = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(-60),
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(permissionGrantedDecision)
        ledger.markFailed(identifier: identifier, dueAt: dueAt)
        let failedDecision = ledger.shouldSchedule(
            identifier: identifier,
            dueAt: dueAt,
            now: dueAt.addingTimeInterval(-30),
            pendingIDs: [],
            deliveredIDs: [],
            authorizationAvailable: true
        )
        #expect(!failedDecision)
    }
}
