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

@Suite("SmartMailboxSettings")
struct SmartMailboxSettingsTests {
    @Test("built-in Smart Views default on and persist individual visibility")
    func builtInVisibilityRoundTrips() throws {
        let defaults = try Self.makeDefaults()
        var settings = SmartMailboxSettings.defaults

        #expect(settings.isBuiltInEnabled("today"))
        settings.setBuiltIn("today", isEnabled: false)
        settings.save(to: defaults)

        let restored = SmartMailboxSettings.load(from: defaults)
        #expect(!restored.isBuiltInEnabled("today"))
        #expect(restored.isBuiltInEnabled("flagged"))
    }

    @Test("defaults has no smart mailboxes")
    func defaultsIsEmpty() throws {
        let defaults = try Self.makeDefaults()
        let settings = SmartMailboxSettings.load(from: defaults)
        #expect(settings.mailboxes.isEmpty)
    }

    @Test("add and remove smart mailboxes persist")
    func addAndRemovePersist() throws {
        let defaults = try Self.makeDefaults()
        var settings = SmartMailboxSettings.defaults
        let query = SmartMailbox.SavedQuery(text: "from:boss", isUnread: true)
        let mailbox = SmartMailbox(id: "smart-1", name: "From Boss", query: query, isEnabled: true)

        settings.add(mailbox)
        settings.save(to: defaults)
        let restored = SmartMailboxSettings.load(from: defaults)

        #expect(restored.mailboxes.count == 1)
        #expect(restored.mailboxes[0].name == "From Boss")
        #expect(restored.mailboxes[0].kind == .messageSearch)

        settings.remove(id: "smart-1")
        settings.save(to: defaults)
        let afterRemove = SmartMailboxSettings.load(from: defaults)
        #expect(afterRemove.mailboxes.isEmpty)
    }

    @Test("update modifies existing smart mailbox")
    func updateModifiesExisting() throws {
        var settings = SmartMailboxSettings.defaults
        let query = SmartMailbox.SavedQuery(text: "is:unread")
        let mailbox = SmartMailbox(id: "smart-1", name: "Unread", query: query, isEnabled: true)
        settings.add(mailbox)

        var updated = mailbox
        updated.name = "Updated Name"
        settings.update(updated)

        #expect(settings.mailboxes[0].name == "Updated Name")
    }

    @Test("corrupt persisted smart mailbox data falls back to defaults")
    func corruptDataFallsBack() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: SmartMailboxSettings.Key.mailboxes)

        let settings = SmartMailboxSettings.load(from: defaults)
        #expect(settings == .defaults)
    }

    @Test("saved query converts to backend search query")
    func savedQueryConvertsToBackendSearchQuery() {
        let saved = SmartMailbox.SavedQuery(
            text: "invoice",
            from: "boss@example.com",
            to: "me@example.com",
            hasAttachment: true,
            isUnread: true,
            isStarred: true,
            folderID: "inbox"
        )

        let query = saved.searchQuery
        #expect(query.text == "invoice")
        #expect(query.from == "boss@example.com")
        #expect(query.to == "me@example.com")
        #expect(query.hasAttachments == true)
        #expect(query.isUnread == true)
        #expect(query.isFlagged == true)
        #expect(query.folderID == "inbox")
    }

    @Test("smart mailbox kind separates message searches from attachment smart views")
    func smartMailboxKindSeparatesMessageSearchesFromAttachmentSmartViews() throws {
        let defaults = try Self.makeDefaults()
        let attachmentMailbox = SmartMailbox(
            id: "smart-attachments",
            name: "All Attachments",
            kind: .attachmentSearch,
            query: SmartMailbox.SavedQuery(text: "", hasAttachment: true),
            isEnabled: true
        )
        var settings = SmartMailboxSettings.defaults
        settings.add(attachmentMailbox)

        settings.save(to: defaults)
        let restored = SmartMailboxSettings.load(from: defaults)

        #expect(restored.mailboxes.first?.kind == .attachmentSearch)
        #expect(restored.mailboxes.first?.query.hasAttachment == true)
    }

    @Test("legacy smart mailbox payloads decode as message searches")
    func legacySmartMailboxPayloadsDecodeAsMessageSearches() throws {
        let json = """
        {
          "mailboxes": [
            {
              "id": "legacy",
              "name": "Unread invoices",
              "query": {
                "text": "invoice",
                "isUnread": true
              },
              "isEnabled": true
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(SmartMailboxSettings.self, from: data)

        #expect(settings.mailboxes.first?.kind == .messageSearch)
        #expect(settings.isBuiltInEnabled("today"))
    }

    @Test("execution is deterministic and honors persisted mailbox order")
    func executionIsDeterministicAndHonorsPersistedOrder() {
        let unread = SmartMailbox(
            id: "smart-unread",
            name: "Unread",
            query: SmartMailbox.SavedQuery(text: "", isUnread: true),
            isEnabled: true
        )
        let disabled = SmartMailbox(
            id: "smart-disabled",
            name: "Disabled",
            query: SmartMailbox.SavedQuery(text: "", isUnread: true),
            isEnabled: false
        )
        let fromBoss = SmartMailbox(
            id: "smart-boss",
            name: "From boss",
            query: SmartMailbox.SavedQuery(text: "", from: "boss@example.com"),
            isEnabled: true
        )
        let settings = SmartMailboxSettings(mailboxes: [unread, disabled, fromBoss])

        let oldUnread = Self.makeHeader(
            id: "m-old",
            date: Date(timeIntervalSince1970: 10),
            from: Correspondent(name: "Boss", email: "boss@example.com"),
            isRead: false
        )
        let newRead = Self.makeHeader(
            id: "m-new",
            date: Date(timeIntervalSince1970: 20),
            from: Correspondent(name: "Boss", email: "boss@example.com"),
            isRead: true
        )
        let newUnread = Self.makeHeader(
            id: "m-new-unread",
            date: Date(timeIntervalSince1970: 20),
            from: Correspondent(name: "Colleague", email: "colleague@example.com"),
            isRead: false
        )

        let firstRun = settings.execute(on: [oldUnread, newRead, newUnread])
        let secondRun = settings.execute(on: [newUnread, oldUnread, newRead])

        #expect(firstRun == secondRun)
        #expect(firstRun.map(\.mailboxID) == ["smart-unread", "smart-boss"])
        #expect(firstRun[0].messageIDs == ["m-new-unread", "m-old"])
        #expect(firstRun[1].messageIDs == ["m-new", "m-old"])
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suite = "SmartMailboxSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func makeHeader(
        id: String,
        date: Date,
        from: Correspondent,
        isRead: Bool
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: from,
            to: [Correspondent(email: "me@example.com")],
            subject: "Status",
            snippet: "Weekly status update",
            date: date,
            isRead: isRead,
            isFlagged: false
        )
    }
}
