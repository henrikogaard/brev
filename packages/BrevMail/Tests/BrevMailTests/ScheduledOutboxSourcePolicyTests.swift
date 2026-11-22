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

    @Test("same context transition is idempotent in either lifecycle ordering")
    func sameContextTransitionIsIdempotent() {
        let backend = NSObject()
        let source = MailSourceID(accountID: "account", mailboxID: "a")
        let context = ScheduledOutboxContext(backendID: ObjectIdentifier(backend), sourceID: source)

        var changeThenTask = ScheduledOutboxContextTransition()
        let onChangeStarted = changeThenTask.transition(to: context)
        #expect(onChangeStarted)
        let changeGeneration = changeThenTask.generation
        let taskStartedNewGeneration = changeThenTask.transition(to: context)
        #expect(!taskStartedNewGeneration)
        #expect(changeThenTask.generation == changeGeneration)

        var taskThenChange = ScheduledOutboxContextTransition()
        let taskStarted = taskThenChange.transition(to: context)
        #expect(taskStarted)
        let taskGeneration = taskThenChange.generation
        let onChangeStartedNewGeneration = taskThenChange.transition(to: context)
        #expect(!onChangeStartedNewGeneration)
        #expect(taskThenChange.generation == taskGeneration)
        #expect(taskThenChange.generation == changeThenTask.generation)
    }

    @Test("an old Outbox context cannot publish under a newer transition")
    func oldContextCannotPublishAfterTransition() {
        let backend = NSObject()
        let sourceA = MailSourceID(accountID: "account", mailboxID: "a")
        let sourceB = MailSourceID(accountID: "account", mailboxID: "b")
        let oldContext = ScheduledOutboxContext(backendID: ObjectIdentifier(backend), sourceID: sourceA)
        let newContext = ScheduledOutboxContext(backendID: ObjectIdentifier(backend), sourceID: sourceB)
        var transition = ScheduledOutboxContextTransition()
        let firstContextChanged = transition.transition(to: oldContext)
        #expect(firstContextChanged)
        let oldGeneration = transition.generation
        let secondContextChanged = transition.transition(to: newContext)
        #expect(secondContextChanged)

        #expect(!ScheduledOutboxSourcePolicy.isCurrent(
            requested: oldContext,
            current: newContext,
            generation: oldGeneration,
            currentGeneration: transition.generation,
            isCancelled: false
        ))
        #expect(ScheduledOutboxSourcePolicy.isCurrent(
            requested: newContext,
            current: newContext,
            generation: transition.generation,
            currentGeneration: transition.generation,
            isCancelled: false
        ))
    }
}
