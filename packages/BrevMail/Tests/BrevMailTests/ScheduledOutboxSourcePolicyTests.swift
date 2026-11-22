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
import Foundation
import Testing

@Suite("Scheduled Outbox source selection")
struct ScheduledOutboxSourcePolicyTests {
    @Test("shows only the selected owner plus legacy ownerless schedules")
    func selectedSourceKeepsLegacyEntries() {
        let sourceA = MailSourceID(accountID: "account", mailboxID: "a")
        let sourceB = MailSourceID(accountID: "account", mailboxID: "b")
        let entries = [
            PendingScheduledSend(draftID: "a", scheduledFor: .distantFuture, id: "schedule-a", sourceID: sourceA),
            PendingScheduledSend(draftID: "b", scheduledFor: .distantFuture, id: "schedule-b", sourceID: sourceB),
            PendingScheduledSend(draftID: "legacy", scheduledFor: .distantFuture)
        ]

        #expect(ScheduledOutboxSourcePolicy.visibleEntries(entries, selectedSourceID: sourceA).map(\.id) == [
            "schedule-a",
            "legacy"
        ])
        #expect(ScheduledOutboxSourcePolicy.visibleEntries(entries, selectedSourceID: sourceB).map(\.id) == [
            "schedule-b",
            "legacy"
        ])
        #expect(ScheduledOutboxSourcePolicy.visibleEntries(entries, selectedSourceID: nil).map(\.id) == ["legacy"])
    }

    @Test("a loaded Outbox context cannot publish or act after backend or source changes")
    func staleContextRejectsActionsAndPublications() {
        let backendA = NSObject()
        let backendB = NSObject()
        let sourceA = MailSourceID(accountID: "account", mailboxID: "a")
        let sourceB = MailSourceID(accountID: "account", mailboxID: "b")
        let contextA = ScheduledOutboxContext(backendID: ObjectIdentifier(backendA), sourceID: sourceA)
        let contextB = ScheduledOutboxContext(backendID: ObjectIdentifier(backendA), sourceID: sourceB)
        let otherBackend = ScheduledOutboxContext(backendID: ObjectIdentifier(backendB), sourceID: sourceA)

        #expect(ScheduledOutboxSourcePolicy.isCurrent(
            requested: contextA,
            current: contextA,
            generation: 4,
            currentGeneration: 4,
            isCancelled: false
        ))
        #expect(!ScheduledOutboxSourcePolicy.isCurrent(
            requested: contextA,
            current: contextB,
            generation: 4,
            currentGeneration: 5,
            isCancelled: false
        ))
        #expect(!ScheduledOutboxSourcePolicy.isCurrent(
            requested: contextA,
            current: otherBackend,
            generation: 4,
            currentGeneration: 4,
            isCancelled: false
        ))
        #expect(!ScheduledOutboxSourcePolicy.isCurrent(
            requested: contextA,
            current: contextA,
            generation: 4,
            currentGeneration: 4,
            isCancelled: true
        ))
        #expect(ScheduledOutboxSourcePolicy.isLoaded(
            loaded: contextA,
            requested: contextA,
            loadedGeneration: 4,
            currentGeneration: 4
        ))
        #expect(!ScheduledOutboxSourcePolicy.isLoaded(
            loaded: contextA,
            requested: contextB,
            loadedGeneration: 4,
            currentGeneration: 4
        ))
    }
}
