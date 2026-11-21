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
@testable import BrevSettings
import Foundation
import Testing

@Suite("No-reply follow-up settings")
struct NoReplyFollowUpSettingsTests {
    @Test("old settings decode without pending intents and automatic metadata")
    func oldSettingsDecode() throws {
        let data = Data(#"{"reminders":[{"id":"manual","messageID":"m","threadID":"t","dueAt":0,"isDismissed":false,"isCompleted":false,"createdAt":0}]}"#
            .utf8)
        let settings = try JSONDecoder().decode(FollowUpSettings.self, from: data)

        #expect(settings.pendingNoReplyIntents.isEmpty)
        #expect(settings.reminders.first?.noReplyMetadata == nil)
    }

    @Test("pending intents round-trip and deduplicate by exact source and draft")
    func pendingIntentsRoundTripAndDeduplicate() throws {
        let source = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let intent = PendingNoReplyFollowUpIntent(
            sourceID: source,
            draftID: "draft",
            expectedMessageID: "<brev-draft@example.org>",
            sentMessageIDHint: "SENT:8"
        )
        var settings = FollowUpSettings(reminders: [])
        settings.upsertPendingNoReplyIntent(intent)
        settings.upsertPendingNoReplyIntent(intent)
        let decoded = try JSONDecoder().decode(FollowUpSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.pendingNoReplyIntents == [intent])
        #expect(decoded.pendingNoReplyIntents[0].sourceID == source)
        #expect(PendingNoReplyFollowUpIntent.stableID(
            sourceID: MailSourceID(accountID: "other", mailboxID: "mailbox"), draftID: "draft"
        ) != intent.id)
    }

    @Test("account cleanup removes its pending and scoped reminders but keeps global manual reminders")
    func accountCleanup() {
        let suiteName = "NoReplyFollowUpSettingsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let source = MailSourceID(accountID: "removed", mailboxID: "mailbox")
        var settings = FollowUpSettings(reminders: [
            FollowUpReminder(
                id: "scoped",
                messageID: "m",
                threadID: "t",
                accountID: "removed",
                mailboxID: "mailbox",
                dueAt: .distantFuture
            ),
            FollowUpReminder(
                id: "automatic",
                messageID: "automatic-message",
                threadID: "automatic-thread",
                accountID: "removed",
                mailboxID: "mailbox",
                dueAt: .distantFuture,
                noReplyMetadata: NoReplyFollowUpMetadata(
                    sourceID: source,
                    draftID: "d",
                    expectedMessageID: "<d@example.org>",
                    sentAt: .now
                )
            ),
            FollowUpReminder(id: "global", messageID: "g", threadID: "g", dueAt: .distantFuture)
        ])
        settings.upsertPendingNoReplyIntent(PendingNoReplyFollowUpIntent(
            sourceID: source, draftID: "d", expectedMessageID: "<d@example.org>"
        ))
        settings.save(to: defaults)

        SettingsPersistenceStore(defaults: defaults).removeAccountScopedState(accountID: "removed")
        let cleaned = FollowUpSettings.load(from: defaults)

        #expect(cleaned.pendingNoReplyIntents.isEmpty)
        #expect(cleaned.reminders.map(\.id) == ["global"])
    }
}
