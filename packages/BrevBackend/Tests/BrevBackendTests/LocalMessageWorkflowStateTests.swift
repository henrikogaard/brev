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
import Foundation
import Testing

@Suite("LocalMessageWorkflowState")
struct LocalMessageWorkflowStateTests {
    private let work = MailSourceID(accountID: "acct-1", mailboxID: "work")
    private let personal = MailSourceID(accountID: "acct-1", mailboxID: "personal")
    private let otherAccount = MailSourceID(accountID: "acct-2", mailboxID: "shared")

    @Test("snoozes are scoped by source and expire at wake time")
    func snoozesAreScopedBySourceAndExpireAtWakeTime() {
        let now = Date(timeIntervalSince1970: 1000)
        let workMessage = SourceMessageID(sourceID: work, messageID: "same-provider-id")
        let personalMessage = SourceMessageID(sourceID: personal, messageID: "same-provider-id")

        let state = LocalMessageWorkflowStatePolicy.snoozing(
            workMessage,
            until: now.addingTimeInterval(3600),
            now: now,
            in: .defaults
        )

        #expect(state.activeSnooze(for: workMessage, at: now) != nil)
        #expect(state.activeSnooze(for: personalMessage, at: now) == nil)
        #expect(!state.isSnoozed(workMessage, at: now.addingTimeInterval(3600)))
    }

    @Test("mark as done is separate from snooze and can be cleared for undo")
    func markAsDoneIsSeparateFromSnoozeAndCanBeClearedForUndo() {
        let now = Date(timeIntervalSince1970: 2000)
        let message = SourceMessageID(sourceID: work, messageID: "message-1")
        let snoozed = LocalMessageWorkflowStatePolicy.snoozing(
            message,
            until: now.addingTimeInterval(3600),
            now: now,
            in: .defaults
        )
        let done = LocalMessageWorkflowStatePolicy.markingDone([message], now: now, in: snoozed)
        let undone = LocalMessageWorkflowStatePolicy.clearingDone([message], in: done)

        #expect(done.isDone(message))
        #expect(done.isSnoozed(message, at: now))
        #expect(!undone.isDone(message))
        #expect(undone.isSnoozed(message, at: now))
    }

    @Test("message notes are source scoped and empty notes remove existing notes")
    func messageNotesAreSourceScopedAndEmptyNotesRemoveExistingNotes() {
        let now = Date(timeIntervalSince1970: 2500)
        let workMessage = SourceMessageID(sourceID: work, messageID: "same-provider-id")
        let personalMessage = SourceMessageID(sourceID: personal, messageID: "same-provider-id")

        let noted = LocalMessageWorkflowStatePolicy.savingNote(
            for: workMessage,
            body: "  Follow up after launch.  ",
            now: now,
            in: .defaults
        )

        #expect(noted.note(for: workMessage)?.body == "Follow up after launch.")
        #expect(noted.note(for: workMessage)?.createdAt == now)
        #expect(noted.note(for: workMessage)?.updatedAt == now)
        #expect(noted.note(for: personalMessage) == nil)

        let removed = LocalMessageWorkflowStatePolicy.savingNote(
            for: workMessage,
            body: "   ",
            now: now.addingTimeInterval(60),
            in: noted
        )

        #expect(removed.note(for: workMessage) == nil)
    }

    @Test("storage round trips local workflow state")
    func storageRoundTripsLocalWorkflowState() throws {
        let defaults = try Self.makeDefaults()
        let now = Date(timeIntervalSince1970: 3000)
        let message = SourceMessageID(sourceID: work, messageID: "message-1")
        let workflowState = LocalMessageWorkflowStatePolicy.markingDone(
            [message],
            now: now,
            in: LocalMessageWorkflowStatePolicy.snoozing(
                message,
                until: now.addingTimeInterval(7200),
                now: now,
                in: .defaults
            )
        )
        let state = LocalMessageWorkflowStatePolicy.savingNote(
            for: message,
            body: "Retain this locally.",
            now: now,
            in: workflowState
        )

        LocalMessageWorkflowStateStorage.save(state, to: defaults)

        #expect(LocalMessageWorkflowStateStorage.load(from: defaults) == state)
    }

    @Test("storage removes workflow state for signed out accounts")
    func storageRemovesWorkflowStateForSignedOutAccounts() throws {
        let defaults = try Self.makeDefaults()
        let now = Date(timeIntervalSince1970: 4000)
        let signedOutMessage = SourceMessageID(sourceID: work, messageID: "message-1")
        let retainedMessage = SourceMessageID(sourceID: otherAccount, messageID: "message-2")
        let state = LocalMessageWorkflowStatePolicy.markingDone(
            [signedOutMessage, retainedMessage],
            now: now,
            in: LocalMessageWorkflowStatePolicy.snoozing(
                signedOutMessage,
                until: now.addingTimeInterval(3600),
                now: now,
                in: .defaults
            )
        )

        LocalMessageWorkflowStateStorage.save(state, to: defaults)
        LocalMessageWorkflowStateStorage.removeAccount("acct-1", from: defaults)

        #expect(LocalMessageWorkflowStateStorage.load(from: defaults) == LocalMessageWorkflowState(
            snoozes: [],
            doneMessages: [
                LocalMessageDone(messageID: retainedMessage, completedAt: now)
            ],
            notes: []
        ))
    }

    @Test("storage decodes legacy workflow state with no notes")
    func storageDecodesLegacyWorkflowStateWithNoNotes() throws {
        let message = SourceMessageID(sourceID: work, messageID: "message-1")
        let json = """
        {
          "snoozes": [],
          "doneMessages": [
            {
              "messageID": {
                "sourceID": { "accountID": "\(message.sourceID.accountID)", "mailboxID": "\(message.sourceID.mailboxID)" },
                "messageID": "\(message.messageID)"
              },
              "completedAt": 3000
            }
          ]
        }
        """
        let state = try #require(LocalMessageWorkflowStateStorage.decode(Data(json.utf8)))

        #expect(state.isDone(message))
        #expect(state.notes.isEmpty)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "LocalMessageWorkflowStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
