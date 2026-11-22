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
import BrevSettings
import Foundation
import Testing

@Suite("No-reply follow-up reconciliation")
struct NoReplyFollowUpReconcilerTests {
    private let source = MailSourceID(accountID: "acct", mailboxID: "box")
    private let otherSource = MailSourceID(accountID: "other", mailboxID: "box")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = Correspondent(email: "me@example.org")
    private let other = Correspondent(email: "you@example.org")

    private func header(
        _ id: String,
        folder: String,
        messageID: String? = nil,
        threadID: String? = nil,
        subject: String = "Same subject",
        from: Correspondent? = nil,
        inReplyTo: String? = nil,
        references: [String]? = nil,
        date: Date? = nil
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID ?? id,
            folderID: folder,
            from: from ?? other,
            to: [me],
            subject: subject,
            snippet: "body",
            date: date ?? now,
            messageID: messageID,
            inReplyTo: inReplyTo,
            references: references
        )
    }

    private func intent(source: MailSourceID? = nil, hint: String? = nil) -> PendingNoReplyFollowUpIntent {
        PendingNoReplyFollowUpIntent(
            sourceID: source ?? self.source,
            draftID: "draft",
            expectedMessageID: "<out@example.org>",
            sentMessageIDHint: hint
        )
    }

    private func snapshot(
        source: MailSourceID? = nil,
        headers: [MessageHeader],
        complete: Bool = true
    ) -> NoReplyFollowUpCacheSnapshot {
        NoReplyFollowUpCacheSnapshot(
            sourceID: source ?? self.source,
            headers: headers,
            sentFolderIDs: ["sent"],
            ownAddresses: ["me@example.org"],
            isComplete: complete
        )
    }

    @Test("exact source and RFC identity are required; already cached replies prevent creation")
    func exactSourceRFCAndExistingReply() {
        var settings = FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()])
        let wrongSourceCopy = header("wrong", folder: "sent", messageID: "<out@example.org>")
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>")
        let unrelated = header("unrelated", folder: "archive", messageID: "<unrelated@x>")
        let reply = header(
            "reply", folder: "inbox", messageID: "<reply@x>", inReplyTo: "<out@example.org>",
            date: now.addingTimeInterval(60)
        )
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [
                snapshot(source: otherSource, headers: [wrongSourceCopy]),
                snapshot(headers: [sent, unrelated, reply])
            ]
        )

        settings = result.settings
        #expect(settings.reminders.count == 1)
        #expect(settings.reminders[0].isCompleted)
        #expect(settings.reminders[0].noReplyMetadata?.sourceID == source)
        #expect(settings.pendingNoReplyIntents.isEmpty)
        #expect(result.created.isEmpty)
    }

    @Test("an exact References link completes despite a backdated reply and survives cache eviction")
    func backdatedReferenceCompletesAndLeavesTombstone() {
        let sentAt = now
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()]),
            snapshots: [snapshot(headers: [
                header("sent-id", folder: "sent", messageID: "<out@example.org>", date: sentAt),
                header(
                    "earlier", folder: "inbox", messageID: "<earlier@x>",
                    references: ["<out@example.org>"], date: sentAt.addingTimeInterval(-60)
                )
            ])]
        )

        #expect(result.created.isEmpty)
        #expect(result.settings.pendingNoReplyIntents.isEmpty)
        #expect(result.settings.reminders.count == 1)
        #expect(result.settings.reminders[0].isCompleted)

        let replay = NoReplyFollowUpReconciler.reconcile(
            settings: result.settings,
            snapshots: [snapshot(headers: [
                header("sent-id", folder: "sent", messageID: "<out@example.org>", date: sentAt)
            ])]
        )
        #expect(replay.settings.reminders.count == 1)
        #expect(replay.settings.reminders[0].isCompleted)
        #expect(replay.created.isEmpty)
    }

    @Test("References tokens are parsed independently and malformed tokens do not poison valid links")
    func referencesTokensAreParsedIndependently() {
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>")
        let reply = header(
            "reply", folder: "inbox", messageID: "<reply@x>",
            references: ["out@example.org", "<another@x>", "<malformed", "<out@example.org>"]
        )
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()]),
            snapshots: [snapshot(headers: [sent, reply])]
        )

        #expect(result.created.isEmpty)
        #expect(result.settings.reminders.count == 1)
        #expect(result.settings.reminders[0].isCompleted)
    }

    @Test("matching subject without exact reply references does not complete the reminder")
    func subjectDoesNotCompleteReminder() {
        let settings = FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()])
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>")
        let sameSubject = header("same-subject", folder: "inbox", messageID: "<other@x>")
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [snapshot(headers: [sent, sameSubject])]
        )

        #expect(result.created.count == 1)
        #expect(!result.created[0].isCompleted)
    }

    @Test("missing RFC metadata keeps the accepted intent pending")
    func missingMessageIDDoesNotCreateReminder() {
        let settings = FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()])
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [snapshot(headers: [header("sent-id", folder: "sent")])]
        )

        #expect(result.created.isEmpty)
        #expect(result.settings.pendingNoReplyIntents == [intent()])
    }

    @Test("a multi-identifier Message-ID is not treated as one exact RFC identity")
    func multipleIdentifiersDoNotMatch() {
        let malformedIntent = PendingNoReplyFollowUpIntent(
            sourceID: source,
            draftID: "draft",
            expectedMessageID: "<out@example.org> <other@example.org>"
        )
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: FollowUpSettings(reminders: [], pendingNoReplyIntents: [malformedIntent]),
            snapshots: [snapshot(headers: [header("sent-id", folder: "sent", messageID: "<out@example.org>")])]
        )

        #expect(result.created.isEmpty)
        #expect(result.settings.pendingNoReplyIntents == [malformedIntent])
    }

    @Test("a cached later reply completes an active reminder in the same pass")
    func cachedReplyCompletesActiveReminder() {
        let sentAt = now.addingTimeInterval(-3600)
        let intent = intent()
        let reminder = FollowUpReminder(
            id: intent.id,
            messageID: "sent-id",
            threadID: "sent-id",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: "sent",
            dueAt: now,
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source, draftID: intent.draftID,
                expectedMessageID: intent.expectedMessageID, sentAt: sentAt
            )
        )
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>", date: sentAt)
        let reply = header(
            "reply", folder: "inbox", messageID: "<reply@x>",
            references: ["<out@example.org>"], date: now
        )
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: FollowUpSettings(reminders: [reminder]),
            snapshots: [snapshot(headers: [sent, reply])]
        )

        #expect(result.settings.reminders.first?.isCompleted == true)
        #expect(result.completed.map(\.id) == [reminder.id])
    }

    @Test("scheduled cancellation removes only the exact source and draft intent")
    func scheduledCancellationRemovesMatchingIntent() {
        var settings = FollowUpSettings(reminders: [], pendingNoReplyIntents: [
            intent(),
            intent(source: otherSource)
        ])
        settings.removePendingNoReplyIntent(sourceID: source, draftID: "draft")

        #expect(settings.pendingNoReplyIntents.map(\.sourceID) == [otherSource])
    }

    @Test("automatic reminders require their exact source instead of legacy fallback")
    func automaticReminderLookupIsSourceExact() {
        let intent = intent()
        let reminder = FollowUpReminder(
            id: intent.id,
            messageID: "sent-id",
            threadID: "sent-id",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            dueAt: now,
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source,
                draftID: intent.draftID,
                expectedMessageID: intent.expectedMessageID,
                sentAt: now
            )
        )
        let settings = FollowUpSettings(reminders: [reminder])

        #expect(settings.reminder(for: "sent-id") == nil)
        #expect(settings.reminder(for: "sent-id", sourceID: nil) == nil)
        #expect(settings.reminder(for: "sent-id", sourceID: otherSource) == nil)
        #expect(settings.reminder(for: "sent-id", sourceID: source)?.id == reminder.id)
    }

    @Test("legacy manual reminders stay manual and automatic metadata round-trips")
    func legacyDecodeAndAutomaticRoundTrip() throws {
        let legacy = Data(
            #"{"reminders":[{"id":"manual","messageID":"m","threadID":"t","dueAt":0,"isDismissed":false,"isCompleted":false,"createdAt":0}]}"#
                .utf8
        )
        let decodedLegacy = try JSONDecoder().decode(FollowUpSettings.self, from: legacy)
        #expect(decodedLegacy.pendingNoReplyIntents.isEmpty)
        #expect(decodedLegacy.reminders.first?.noReplyMetadata == nil)
        #expect(decodedLegacy.reminders.first?.isAutomaticNoReply == false)

        let automatic = FollowUpReminder(
            id: "automatic",
            messageID: "sent-id",
            threadID: "sent-id",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: "sent",
            dueAt: now,
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source, draftID: "draft", expectedMessageID: "<out@example.org>", sentAt: now
            )
        )
        let settings = FollowUpSettings(reminders: [automatic], pendingNoReplyIntents: [intent()])
        let decoded = try JSONDecoder().decode(FollowUpSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)

        let encodedIntent = try JSONEncoder().encode(intent())
        var intentObject = try #require(JSONSerialization.jsonObject(with: encodedIntent) as? [String: Any])
        intentObject["delay"] = 60
        let modifiedIntent = try JSONSerialization.data(withJSONObject: intentObject)
        let decodedIntent = try JSONDecoder().decode(PendingNoReplyFollowUpIntent.self, from: modifiedIntent)
        #expect(decodedIntent.delay == DraftNoReplyFollowUpRequest.threeDayDelay)
    }

    @Test("the Sent header date, not submission time, determines the three-day due date")
    func dueDateUsesActualSentDate() {
        let sentAt = now.addingTimeInterval(24 * 60 * 60)
        let settings = FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()])
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [snapshot(headers: [header("sent-id", folder: "sent", messageID: "<out@example.org>", date: sentAt)])]
        )

        #expect(result.created.count == 1)
        #expect(result.created[0].dueAt == sentAt.addingTimeInterval(DraftNoReplyFollowUpRequest.threeDayDelay))
        #expect(result.created[0].sourceID == source)
    }

    @Test("an exact sent locator hint cannot override a different RFC Message-ID")
    func locatorHintRequiresCanonicalRFCID() {
        let settings = FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent(hint: "sent-id")])
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [snapshot(headers: [header("sent-id", folder: "sent", messageID: "<other@x>")])]
        )

        #expect(result.created.isEmpty)
        #expect(result.settings.pendingNoReplyIntents.count == 1)
    }

    @Test("identical Sent duplicates resolve deterministically")
    func identicalSentDuplicatesResolveDeterministically() {
        let settings = FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()])
        let copies = [
            header("z-copy", folder: "sent", messageID: "<out@example.org>", threadID: "thread"),
            header("a-copy", folder: "sent", messageID: "<out@example.org>", threadID: "thread")
        ]

        let result = NoReplyFollowUpReconciler.reconcile(settings: settings, snapshots: [snapshot(headers: copies)])

        #expect(result.created.map(\.messageID) == ["a-copy"])
        #expect(result.settings.pendingNoReplyIntents.isEmpty)
    }

    @Test("conflicting Sent duplicates stay pending unless an exact locator hint selects a valid copy")
    func conflictingSentDuplicatesRequireValidHint() {
        let copies = [
            header("hinted-copy", folder: "sent", messageID: "<out@example.org>", threadID: "thread-a"),
            header("other-copy", folder: "sent", messageID: "<out@example.org>", threadID: "thread-b", subject: "Conflict")
        ]
        let withoutHint = NoReplyFollowUpReconciler.reconcile(
            settings: FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent()]),
            snapshots: [snapshot(headers: copies)]
        )
        let withHint = NoReplyFollowUpReconciler.reconcile(
            settings: FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent(hint: "hinted-copy")]),
            snapshots: [snapshot(headers: copies)]
        )

        #expect(withoutHint.created.isEmpty)
        #expect(withoutHint.settings.pendingNoReplyIntents.count == 1)
        #expect(withHint.created.map(\.messageID) == ["hinted-copy"])
        #expect(withHint.settings.pendingNoReplyIntents.isEmpty)
    }

    @Test("self and Sent copies do not complete an active reminder")
    func selfAndSentCopiesAreExcluded() {
        let intent = intent()
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>", from: me)
        let selfCopy = header("self-copy", folder: "inbox", messageID: "<copy@x>", from: me, inReplyTo: "<out@example.org>")
        let sentCopy = header(
            "sent-copy",
            folder: "sent",
            messageID: "<self-reply@x>",
            from: other,
            inReplyTo: "<out@example.org>"
        )
        let created = NoReplyFollowUpReconciler.reconcile(
            settings: FollowUpSettings(reminders: [], pendingNoReplyIntents: [intent]),
            snapshots: [snapshot(headers: [sent, selfCopy, sentCopy])]
        )
        var settings = created.settings
        settings.pendingNoReplyIntents = [intent]
        let replay = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [snapshot(headers: [sent, selfCopy, sentCopy])]
        )

        #expect(!replay.settings.reminders[0].isCompleted)
        #expect(replay.created.isEmpty)
        #expect(settings.reminders.first?.id == intent.id)
    }

    @Test("incomplete cache reads preserve pending and active state")
    func incompleteCachePreservesState() {
        let intent = intent()
        let reminder = FollowUpReminder(
            id: intent.id,
            messageID: "sent-id",
            threadID: "sent-id",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: "sent",
            dueAt: now,
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source,
                draftID: intent.draftID,
                expectedMessageID: intent.expectedMessageID,
                sentAt: now
            )
        )
        let settings = FollowUpSettings(reminders: [reminder], pendingNoReplyIntents: [intent])
        let result = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [snapshot(headers: [header("reply", folder: "inbox", inReplyTo: "<out@example.org>")], complete: false)]
        )

        #expect(result.settings == settings)
        #expect(result.completed.isEmpty)
    }

    @Test("replayed intents never resurrect completed or dismissed reminders")
    func replayDoesNotResurrectInactiveReminder() {
        let intent = intent()
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>")
        for inactive in [true, false] {
            let reminder = FollowUpReminder(
                id: intent.id,
                messageID: sent.id,
                threadID: sent.threadID,
                accountID: source.accountID,
                mailboxID: source.mailboxID,
                folderID: sent.folderID,
                dueAt: now,
                isDismissed: inactive,
                isCompleted: !inactive,
                noReplyMetadata: NoReplyFollowUpMetadata(
                    sourceID: source, draftID: intent.draftID,
                    expectedMessageID: intent.expectedMessageID, sentAt: sent.date
                )
            )
            let result = NoReplyFollowUpReconciler.reconcile(
                settings: FollowUpSettings(reminders: [reminder], pendingNoReplyIntents: [intent]),
                snapshots: [snapshot(headers: [sent])]
            )
            #expect(result.settings.reminders == [reminder])
            #expect(result.created.isEmpty)
        }
    }

    @Test("replacing an automatic reminder with a manual one retains its terminal identity")
    func manualReplacementKeepsAutomaticTombstone() {
        let intent = intent()
        let automatic = FollowUpReminder(
            id: intent.id,
            messageID: "sent-id",
            threadID: "thread",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: "sent",
            dueAt: now,
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source, draftID: intent.draftID,
                expectedMessageID: intent.expectedMessageID, sentAt: now
            )
        )
        var settings = FollowUpSettings(reminders: [automatic])
        settings.add(FollowUpReminder(
            messageID: automatic.messageID,
            threadID: automatic.threadID,
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: automatic.folderID,
            dueAt: now.addingTimeInterval(3600)
        ))

        let replay = NoReplyFollowUpReconciler.reconcile(
            settings: settings,
            snapshots: [snapshot(headers: [header("sent-id", folder: "sent", messageID: intent.expectedMessageID)])]
        )

        #expect(replay.settings.reminders.count == 2)
        #expect(replay.settings.reminders.first(where: { $0.id == intent.id })?.isDismissed == true)
        #expect(replay.created.isEmpty)
    }

    @Test("Waiting includes active future reminders from exact cached Sent copies only")
    func waitingProjectionUsesCachedSentHeadersAndSource() {
        let future = FollowUpReminder(
            id: "waiting",
            messageID: "sent-id",
            threadID: "sent-id",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: "sent",
            dueAt: now.addingTimeInterval(86400),
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source, draftID: "draft", expectedMessageID: "<out@example.org>", sentAt: now
            )
        )
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>")
        let duplicate = header("duplicate", folder: "label-sent", messageID: "<out@example.org>")
        let wrongSourceReminder = FollowUpReminder(
            id: "collision", messageID: duplicate.id, threadID: duplicate.threadID,
            accountID: otherSource.accountID, mailboxID: otherSource.mailboxID,
            folderID: duplicate.folderID, dueAt: now,
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: otherSource, draftID: "draft", expectedMessageID: "<out@example.org>", sentAt: now
            )
        )

        let result = NoReplyFollowUpWaitingProjection.headers(
            sourceID: source,
            sentFolderIDs: ["sent"],
            cachedHeaders: [sent, duplicate],
            reminders: [future, wrongSourceReminder]
        )
        #expect(result.map(\.id) == ["sent-id"])
    }

    @Test("Waiting local search filters source-owned Sent membership and clearing restores it")
    func waitingSearchFiltersOnlyProjectedSentMembership() {
        let sent = header(
            "sent-id",
            folder: "sent",
            messageID: "<out@example.org>",
            subject: "Quarterly budget"
        )
        let matchingInbox = header(
            "inbox-match",
            folder: "inbox",
            messageID: "<inbox@example.org>",
            subject: "Quarterly budget"
        )
        let otherSent = header(
            "shared-id",
            folder: "sent",
            messageID: "<out@example.org>",
            subject: "Quarterly budget"
        )
        let reminder = FollowUpReminder(
            id: "waiting",
            messageID: "sent-id",
            threadID: "sent-id",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: "sent",
            dueAt: now.addingTimeInterval(86400),
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source, draftID: "draft", expectedMessageID: "<out@example.org>", sentAt: now
            )
        )
        let otherReminder = FollowUpReminder(
            id: "other-waiting",
            messageID: "shared-id",
            threadID: "shared-id",
            accountID: otherSource.accountID,
            mailboxID: otherSource.mailboxID,
            folderID: "sent",
            dueAt: now.addingTimeInterval(86400),
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: otherSource, draftID: "other-draft", expectedMessageID: "<out@example.org>", sentAt: now
            )
        )
        let reminders = [reminder, otherReminder]
        let waitingHeaders = NoReplyFollowUpWaitingProjection.headers(
            sourceID: source,
            sentFolderIDs: ["sent"],
            cachedHeaders: [sent, matchingInbox],
            reminders: reminders
        )
        let otherWaitingHeaders = NoReplyFollowUpWaitingProjection.headers(
            sourceID: otherSource,
            sentFolderIDs: ["sent"],
            cachedHeaders: [otherSent],
            reminders: reminders
        )
        let foreignReminderCollision = NoReplyFollowUpWaitingProjection.headers(
            sourceID: source,
            sentFolderIDs: ["sent"],
            cachedHeaders: [sent],
            reminders: [otherReminder]
        )

        let query = UnifiedInboxSearchPolicy.waitingSearchQuery(text: "quarterly", now: now)
        let clearedQuery = UnifiedInboxSearchPolicy.waitingSearchQuery(text: " \n", now: now)

        #expect(query.execution == .cacheOnly)
        #expect(query.folderID == nil)
        #expect(query.matches(matchingInbox))
        #expect(query.matches(otherSent))
        #expect(waitingHeaders.map(\.id) == ["sent-id"])
        #expect(waitingHeaders.filter { query.matches($0) }.map(\.id) == ["sent-id"])
        #expect(otherWaitingHeaders.filter { query.matches($0) }.map(\.id) == ["shared-id"])
        #expect(foreignReminderCollision.isEmpty)
        #expect(waitingHeaders.filter { clearedQuery.matches($0) }.map(\.id) == waitingHeaders.map(\.id))
    }

    @Test("Waiting projection drops rows when the reminder is dismissed during cache loading")
    func waitingProjectionUsesLatestReminderState() {
        let reminder = FollowUpReminder(
            id: "waiting",
            messageID: "sent-id",
            threadID: "sent-id",
            accountID: source.accountID,
            mailboxID: source.mailboxID,
            folderID: "sent",
            dueAt: now.addingTimeInterval(86400),
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: source, draftID: "draft", expectedMessageID: "<out@example.org>", sentAt: now
            )
        )
        let sent = header("sent-id", folder: "sent", messageID: "<out@example.org>")
        let activeProjection = NoReplyFollowUpWaitingProjection.headers(
            sourceID: source,
            sentFolderIDs: ["sent"],
            cachedHeaders: [sent],
            reminders: [reminder]
        )
        var latestSettings = FollowUpSettings(reminders: [reminder])
        latestSettings.dismiss(id: reminder.id)
        let afterDismissal = NoReplyFollowUpWaitingProjection.headers(
            sourceID: source,
            sentFolderIDs: ["sent"],
            cachedHeaders: [sent],
            reminders: latestSettings.reminders
        )

        #expect(activeProjection.map(\.id) == ["sent-id"])
        #expect(afterDismissal.isEmpty)
    }

    @Test("same-ID source replacement rejects an old backend callback")
    func sameSourceReplacementRejectsOldBackend() {
        let oldBackend = FollowUpBackendLifetime()
        let replacementBackend = FollowUpBackendLifetime()
        let oldIdentity = ObjectIdentifier(oldBackend)
        let newIdentity = ObjectIdentifier(replacementBackend)

        #expect(!NoReplyFollowUpOwnership.isCurrent(
            sourceID: source,
            currentSourceIDs: Set([source]),
            currentAccountID: source.accountID,
            currentBackendIdentity: newIdentity,
            expectedBackendIdentity: oldIdentity
        ))
        #expect(NoReplyFollowUpOwnership.isCurrent(
            sourceID: source,
            currentSourceIDs: Set([source]),
            currentAccountID: source.accountID,
            currentBackendIdentity: oldIdentity,
            expectedBackendIdentity: oldIdentity
        ))
        #expect(!NoReplyFollowUpOwnership.canApplyRefresh(
            generation: 1,
            currentGeneration: 2,
            sourceSectionsRevision: 5,
            currentSourceSectionsRevision: 5,
            sourceID: source,
            currentSourceIDs: Set([source]),
            currentAccountID: source.accountID,
            currentBackendIdentity: newIdentity,
            expectedBackendIdentity: oldIdentity
        ))
    }
}

private final class FollowUpBackendLifetime {}
