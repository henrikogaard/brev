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

@Suite("Unified Inbox presentation snapshot")
struct UnifiedInboxPresentationSnapshotTests {
    @Test("date sections preserve source identity when message IDs collide")
    func dateSectionsPreserveSourceIdentityWhenMessageIDsCollide() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let personal = Self.item(
            accountID: "personal",
            mailboxID: "primary",
            folder: folder,
            messageID: "shared-provider-id",
            subject: "Personal message",
            date: referenceDate
        )
        let work = Self.item(
            accountID: "work",
            mailboxID: "primary",
            folder: folder,
            messageID: "shared-provider-id",
            subject: "Work message",
            date: referenceDate.addingTimeInterval(-60)
        )

        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [personal, work],
            pinnedMessageIDsRaw: "",
            groupByDate: true,
            collapsedDateSectionIDs: [],
            referenceDate: referenceDate
        )
        let section = try #require(snapshot.dateSections.first)

        #expect(section.visibleItems.map(\.id) == [personal.id, work.id])
        #expect(section.visibleItems.map(\.header.subject) == ["Personal message", "Work message"])
        #expect(snapshot.visibleIndex(for: personal.id) == 0)
        #expect(snapshot.visibleIndex(for: work.id) == 1)
    }

    @Test("pinned IDs are parsed once and collapsed pinned sections hide their rows")
    func pinnedIDsAndCollapsedSectionsAreDerivedTogether() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let pinned = Self.item(
            accountID: "personal",
            mailboxID: "primary",
            folder: folder,
            messageID: "pinned",
            subject: "Pinned message",
            date: referenceDate
        )
        let regular = Self.item(
            accountID: "personal",
            mailboxID: "primary",
            folder: folder,
            messageID: "regular",
            subject: "Regular message",
            date: referenceDate.addingTimeInterval(-60)
        )

        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [pinned, regular],
            pinnedMessageIDsRaw: "pinned\n",
            groupByDate: true,
            collapsedDateSectionIDs: ["Pinned"],
            referenceDate: referenceDate
        )
        let pinnedSection = try #require(snapshot.dateSections.first)
        let regularSection = try #require(snapshot.dateSections.dropFirst().first)

        #expect(snapshot.pinnedMessageIDs == ["pinned"])
        #expect(pinnedSection.title == "Pinned")
        #expect(pinnedSection.totalCount == 1)
        #expect(pinnedSection.isCollapsed)
        #expect(pinnedSection.visibleItems.isEmpty)
        #expect(regularSection.visibleItems.map(\.id) == [regular.id])
    }

    private static func item(
        accountID: String,
        mailboxID: String,
        folder: Folder,
        messageID: String,
        subject: String,
        date: Date
    ) -> UnifiedInboxItem {
        UnifiedInboxItem(
            sourceID: MailSourceID(accountID: accountID, mailboxID: mailboxID),
            folder: folder,
            header: MessageHeader(
                id: messageID,
                threadID: messageID,
                folderID: folder.id,
                from: Correspondent(email: "sender@example.org"),
                subject: subject,
                snippet: "Preview",
                date: date
            ),
            sourceTitle: accountID,
            sourceSubtitle: "\(accountID)@example.org",
            archiveFolder: nil
        )
    }
}

@Suite("UnifiedInbox pinned message persistence")
struct UnifiedInboxPinnedMessagePersistenceTests {
    @Test("complete loads remove pins for messages no longer present")
    func completeLoadPrunesMissingIDs() {
        let result = UnifiedInboxPinnedMessagePersistence.reconciledIDs(
            stored: ["present", "missing"],
            loaded: ["present"],
            isComplete: true
        )

        #expect(result == ["present"])
    }

    @Test("partial loads retain pins outside the loaded page")
    func partialLoadRetainsUnknownIDs() {
        let result = UnifiedInboxPinnedMessagePersistence.reconciledIDs(
            stored: ["loaded", "not-yet-loaded"],
            loaded: ["loaded"],
            isComplete: false
        )

        #expect(result == ["loaded", "not-yet-loaded"])
    }

    @Test("persisted pins are capped deterministically")
    func persistenceIsBounded() {
        let ids = Set((0 ..< UnifiedInboxPinnedMessagePersistence.maximumPersistedCount + 20).map {
            String(format: "id-%04d", $0)
        })
        let result = UnifiedInboxPinnedMessagePersistence.reconciledIDs(
            stored: ids,
            loaded: [],
            isComplete: false
        )

        #expect(result.count == UnifiedInboxPinnedMessagePersistence.maximumPersistedCount)
        #expect(result.contains("id-0000"))
        #expect(!result.contains("id-0519"))
    }
}
