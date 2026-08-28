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

@Suite("VIPSenderSettings")
struct VIPSenderSettingsTests {
    private static func makeDefaults() throws -> UserDefaults {
        let suite = "VIPSenderSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("defaults are empty")
    func defaultsAreEmpty() throws {
        let defaults = try Self.makeDefaults()
        let settings = VIPSenderSettings.load(from: defaults)
        #expect(settings.senders.isEmpty)
    }

    @Test("added sender is recognized as VIP")
    func addedSenderIsVIP() throws {
        var settings = VIPSenderSettings.defaults
        settings.add(VIPSender(email: "alice@example.com"))
        #expect(settings.isVIP(email: "alice@example.com"))
    }

    @Test("email is normalized to lowercase before matching")
    func emailNormalizationForVIPCheck() throws {
        var settings = VIPSenderSettings.defaults
        settings.add(VIPSender(email: "Alice@Example.COM"))
        #expect(settings.isVIP(email: "alice@example.com"))
        #expect(settings.isVIP(email: "ALICE@EXAMPLE.COM"))
    }

    @Test("duplicate add is silently ignored")
    func duplicateAddIsIgnored() throws {
        var settings = VIPSenderSettings.defaults
        settings.add(VIPSender(email: "bob@example.com"))
        settings.add(VIPSender(email: "bob@example.com"))
        #expect(settings.senders.count == 1)
    }

    @Test("remove deletes the sender")
    func removeSender() throws {
        var settings = VIPSenderSettings.defaults
        settings.add(VIPSender(email: "carol@example.com"))
        settings.remove(email: "carol@example.com")
        #expect(!settings.isVIP(email: "carol@example.com"))
        #expect(settings.senders.isEmpty)
    }

    @Test("saving and loading round-trips all fields")
    func saveAndLoadRoundTrips() throws {
        let defaults = try Self.makeDefaults()
        var settings = VIPSenderSettings.defaults
        settings.add(VIPSender(email: "vip@example.com", displayName: "VIP Person"))
        settings.save(to: defaults)

        let loaded = VIPSenderSettings.load(from: defaults)
        #expect(loaded.senders.count == 1)
        #expect(loaded.senders[0].email == "vip@example.com")
        #expect(loaded.senders[0].displayName == "VIP Person")
    }

    @Test("unknown sender is not VIP")
    func unknownSenderIsNotVIP() {
        let settings = VIPSenderSettings.defaults
        #expect(!settings.isVIP(email: "stranger@example.com"))
    }
}

@Suite("FollowUpSettings")
struct FollowUpSettingsTests {
    private static func makeDefaults() throws -> UserDefaults {
        let suite = "FollowUpSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func makeReminder(
        id: String = UUID().uuidString,
        messageID: String = "msg-1",
        dueAt: Date = Date().addingTimeInterval(3600)
    ) -> FollowUpReminder {
        FollowUpReminder(id: id, messageID: messageID, threadID: messageID, dueAt: dueAt)
    }

    @Test("defaults are empty")
    func defaultsAreEmpty() throws {
        let defaults = try Self.makeDefaults()
        let settings = FollowUpSettings.load(from: defaults)
        #expect(settings.reminders.isEmpty)
    }

    @Test("active reminders excludes dismissed and completed entries")
    func activeRemindersExcludesDismissedAndCompleted() {
        var settings = FollowUpSettings.defaults
        let active = Self.makeReminder(id: "r1", messageID: "msg-1")
        let dismissed = Self.makeReminder(id: "r2", messageID: "msg-2")
        let completed = Self.makeReminder(id: "r3", messageID: "msg-3")
        settings.add(active)
        settings.add(dismissed)
        settings.add(completed)
        settings.dismiss(id: "r2")
        settings.complete(id: "r3")

        #expect(settings.activeReminders.count == 1)
        #expect(settings.activeReminders[0].id == "r1")
    }

    @Test("isDue returns true for past and near-future due dates")
    func isDueForPastAndNearFuture() {
        let past = FollowUpReminder(
            messageID: "m1",
            threadID: "m1",
            dueAt: Date().addingTimeInterval(-3600)
        )
        let soon = FollowUpReminder(
            messageID: "m2",
            threadID: "m2",
            dueAt: Date().addingTimeInterval(3600)
        )
        let future = FollowUpReminder(
            messageID: "m3",
            threadID: "m3",
            dueAt: Date().addingTimeInterval(90000)
        )
        #expect(past.isDue())
        #expect(soon.isDue())
        #expect(!future.isDue())
    }

    @Test("add replaces an existing active reminder for the same message")
    func addReplacesExistingActiveReminder() {
        var settings = FollowUpSettings.defaults
        let first = FollowUpReminder(id: "r1", messageID: "msg-x", threadID: "msg-x",
                                     dueAt: Date().addingTimeInterval(3600))
        let second = FollowUpReminder(id: "r2", messageID: "msg-x", threadID: "msg-x",
                                      dueAt: Date().addingTimeInterval(7200))
        settings.add(first)
        settings.add(second)

        #expect(settings.activeReminders.count == 1)
        #expect(settings.activeReminders[0].id == "r2")
    }

    @Test("source-aware reminders do not collide across mailboxes")
    func sourceAwareRemindersDoNotCollideAcrossMailboxes() {
        let sourceA = MailSourceID(accountID: "acct-1", mailboxID: "inbox")
        let sourceB = MailSourceID(accountID: "acct-1", mailboxID: "archive")
        var settings = FollowUpSettings.defaults
        settings.add(FollowUpReminder(
            id: "r-inbox",
            messageID: "same-message",
            threadID: "thread-a",
            accountID: sourceA.accountID,
            mailboxID: sourceA.mailboxID,
            dueAt: Date().addingTimeInterval(3600)
        ))
        settings.add(FollowUpReminder(
            id: "r-archive",
            messageID: "same-message",
            threadID: "thread-b",
            accountID: sourceB.accountID,
            mailboxID: sourceB.mailboxID,
            dueAt: Date().addingTimeInterval(7200)
        ))

        #expect(settings.activeReminders.map(\.id) == ["r-inbox", "r-archive"])
        #expect(settings.reminder(for: "same-message", sourceID: sourceA)?.id == "r-inbox")
        #expect(settings.reminder(for: "same-message", sourceID: sourceB)?.id == "r-archive")
    }

    @Test("source-aware lookup returns the earliest active reminder without sorting all reminders")
    func sourceAwareLookupReturnsEarliestActiveReminder() {
        let source = MailSourceID(accountID: "acct-1", mailboxID: "inbox")
        let settings = FollowUpSettings(reminders: [
            FollowUpReminder(
                id: "later",
                messageID: "same-message",
                threadID: "thread",
                accountID: source.accountID,
                mailboxID: source.mailboxID,
                dueAt: Date(timeIntervalSince1970: 2000)
            ),
            FollowUpReminder(
                id: "earlier",
                messageID: "same-message",
                threadID: "thread",
                accountID: source.accountID,
                mailboxID: source.mailboxID,
                dueAt: Date(timeIntervalSince1970: 1000)
            ),
        ])

        #expect(settings.reminder(for: "same-message", sourceID: source)?.id == "earlier")
    }

    @Test("legacy persisted reminders decode without a mailbox scope")
    func legacyPersistedRemindersDecodeWithoutMailboxScope() throws {
        let defaults = try Self.makeDefaults()
        let legacyJSON = """
        {"reminders":[{"id":"legacy","messageID":"message","threadID":"thread","dueAt":1800000,"isDismissed":false,"isCompleted":false,"createdAt":1800000}]}
        """
        defaults.set(legacyJSON.data(using: .utf8), forKey: FollowUpSettings.Key.reminders)

        let loaded = FollowUpSettings.load(from: defaults)
        #expect(loaded.reminders.count == 1)
        #expect(loaded.reminders[0].mailboxID == nil)
        #expect(loaded.reminders[0].folderID == nil)
    }

    @Test("prune removes old dismissed entries")
    func pruneRemovesOldDismissedEntries() {
        var settings = FollowUpSettings.defaults
        let old = FollowUpReminder(
            id: "r-old",
            messageID: "m1",
            threadID: "m1",
            dueAt: Date().addingTimeInterval(-60 * 86400)
        )
        settings.add(old)
        settings.dismiss(id: "r-old")
        settings.prune(olderThan: Date())

        #expect(settings.reminders.isEmpty)
    }

    @Test("saving and loading round-trips all fields")
    func saveAndLoadRoundTrips() throws {
        let defaults = try Self.makeDefaults()
        var settings = FollowUpSettings.defaults
        let reminder = FollowUpReminder(
            id: "r-persist",
            messageID: "msg-persist",
            threadID: "thread-persist",
            accountID: "acct-1",
            dueAt: Date(timeIntervalSince1970: 1_800_000)
        )
        settings.add(reminder)
        settings.save(to: defaults)

        let loaded = FollowUpSettings.load(from: defaults)
        #expect(loaded.reminders.count == 1)
        #expect(loaded.reminders[0].id == "r-persist")
        #expect(loaded.reminders[0].accountID == "acct-1")
        #expect(loaded.reminders[0].mailboxID == nil)
    }
}

@Suite("MessageTemplateSettings")
struct MessageTemplateSettingsTests {
    private static func makeDefaults() throws -> UserDefaults {
        let suite = "MessageTemplateSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("defaults are empty")
    func defaultsAreEmpty() throws {
        let defaults = try Self.makeDefaults()
        let settings = MessageTemplateSettings.load(from: defaults)
        #expect(settings.templates.isEmpty)
    }

    @Test("templates for nil account includes global templates only")
    func templatesForNilAccountIncludesGlobals() {
        var settings = MessageTemplateSettings.defaults
        settings.add(MessageTemplate(name: "Global", body: "Hello"))
        settings.add(MessageTemplate(name: "Scoped", body: "Hi", accountID: "acct-1"))
        let visible = settings.templates(for: nil)
        #expect(visible.count == 1)
        #expect(visible[0].name == "Global")
    }

    @Test("templates for account includes global plus account-scoped templates")
    func templatesForAccountIncludesGlobalAndScoped() {
        var settings = MessageTemplateSettings.defaults
        settings.add(MessageTemplate(name: "Global", body: "Hello"))
        settings.add(MessageTemplate(name: "Acct1", body: "Hi", accountID: "acct-1"))
        settings.add(MessageTemplate(name: "Acct2", body: "Hey", accountID: "acct-2"))
        let visible = settings.templates(for: "acct-1")
        #expect(visible.count == 2)
        #expect(visible.map(\.name).contains("Global"))
        #expect(visible.map(\.name).contains("Acct1"))
    }

    @Test("pinned templates sort before unpinned")
    func pinnedTemplatesSortFirst() {
        var settings = MessageTemplateSettings.defaults
        settings.add(MessageTemplate(name: "B", body: "", isPinned: false))
        settings.add(MessageTemplate(name: "A", body: "", isPinned: true))
        let sorted = settings.templates(for: nil)
        #expect(sorted[0].isPinned == true)
        #expect(sorted[0].name == "A")
    }

    @Test("togglePin flips the pinned state")
    func togglePinFlipsPinnedState() {
        var settings = MessageTemplateSettings.defaults
        let template = MessageTemplate(name: "T", body: "", isPinned: false)
        settings.add(template)
        settings.togglePin(id: template.id)
        #expect(settings.templates[0].isPinned == true)
        settings.togglePin(id: template.id)
        #expect(settings.templates[0].isPinned == false)
    }

    @Test("update replaces the template in place")
    func updateReplacesTemplate() {
        var settings = MessageTemplateSettings.defaults
        var template = MessageTemplate(name: "Original", body: "Body")
        settings.add(template)
        template.name = "Updated"
        settings.update(template)
        #expect(settings.templates[0].name == "Updated")
        #expect(settings.templates.count == 1)
    }

    @Test("remove deletes by id")
    func removeDeletesById() {
        var settings = MessageTemplateSettings.defaults
        let template = MessageTemplate(name: "Gone", body: "")
        settings.add(template)
        settings.remove(id: template.id)
        #expect(settings.templates.isEmpty)
    }

    @Test("recordUsage updates lastUsedAt")
    func recordUsageUpdatesLastUsedAt() {
        var settings = MessageTemplateSettings.defaults
        let template = MessageTemplate(name: "T", body: "")
        settings.add(template)
        let now = Date(timeIntervalSince1970: 1_000_000)
        settings.recordUsage(id: template.id, at: now)
        #expect(settings.templates[0].lastUsedAt == now)
    }

    @Test("blank names are ignored and duplicate names update within the same scope")
    func blankNamesAreIgnoredAndDuplicatesUpdateWithinScope() {
        var settings = MessageTemplateSettings.defaults
        settings.add(MessageTemplate(name: "   ", body: "Body"))
        settings.add(MessageTemplate(name: "Follow-up", body: "First", accountID: nil))
        settings.add(MessageTemplate(name: " follow-up ", body: "Second", accountID: nil))
        settings.add(MessageTemplate(name: "Follow-up", body: "Account", accountID: "acct-1"))
        settings.add(MessageTemplate(name: "Subject only", body: "   ", subject: "Ping"))
        settings.add(MessageTemplate(name: "Empty content", body: "   ", subject: "   "))

        #expect(settings.templates.count == 4)
        #expect(settings.templates[0].name == "Follow-up")
        #expect(settings.templates[0].body == "Second")
        #expect(settings.templates[0].accountID == nil)
        #expect(settings.templates[1].accountID == "acct-1")
        #expect(settings.templates[2].name == "Subject only")
        #expect(settings.templates[2].subject == "Ping")
        #expect(settings.templates[3].name == "Empty content")
        #expect(settings.templates[3].subject == nil)
    }

    @Test("templates can be reordered without losing account scoping")
    func templatesCanBeReordered() {
        var settings = MessageTemplateSettings.defaults
        let first = MessageTemplate(name: "First", body: "One")
        let second = MessageTemplate(name: "Second", body: "Two")
        let third = MessageTemplate(name: "Third", body: "Three", accountID: "acct-1")
        settings.add(first)
        settings.add(second)
        settings.add(third)

        settings.moveTemplate(id: third.id, direction: .up)
        settings.moveTemplate(id: third.id, direction: .up)
        settings.moveTemplate(id: third.id, direction: .up)

        #expect(settings.templates.map(\.id) == [third.id, first.id, second.id])
        #expect(settings.templates(for: "acct-1").map(\.id) == [third.id, first.id, second.id])

        settings.moveTemplate(id: third.id, direction: .down)
        #expect(settings.templates.map(\.id) == [first.id, third.id, second.id])
    }

    @Test("saving and loading round-trips all fields")
    func saveAndLoadRoundTrips() throws {
        let defaults = try Self.makeDefaults()
        var settings = MessageTemplateSettings.defaults
        settings.add(MessageTemplate(
            name: "Persist",
            body: "Body text",
            subject: "Re: Thing",
            accountID: "acct-x",
            isPinned: true
        ))
        settings.save(to: defaults)

        let loaded = MessageTemplateSettings.load(from: defaults)
        #expect(loaded.templates.count == 1)
        #expect(loaded.templates[0].name == "Persist")
        #expect(loaded.templates[0].subject == "Re: Thing")
        #expect(loaded.templates[0].isPinned == true)
    }
}
