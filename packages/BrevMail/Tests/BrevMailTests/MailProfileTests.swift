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

@Suite("Mail profiles")
struct MailProfileTests {
    @Test("a temporarily unavailable profile retains its membership and selection")
    func unavailableProfileRetainsMembership() {
        let work = Self.sourceID(account: "work", mailbox: "work")
        let personal = Self.section(account: "personal", mailbox: "personal")
        let profile = MailProfile(id: "work", name: "Work", sourceIDs: [work])
        let profiles = MailProfileSelectionPolicy.resolvedProfiles(customProfiles: [profile], availableSourceIDs: [personal.id])
        #expect(profiles.contains(profile))
        #expect(MailProfileSelectionPolicy.selectedProfileID("work", profiles: profiles) == "work")
        #expect(MailProfileSelectionPolicy.visibleSections(from: [personal], activeProfileID: "work", profiles: profiles).isEmpty)
        let saved = MailProfileSelectionPolicy.normalizedCustomProfiles([profile], availableSourceIDs: [])
        #expect(MailProfileStorage.decode(MailProfileStorage.encode(saved)) == [profile])
    }

    @Test("All Mailboxes profile includes every available source")
    func allMailboxesProfileIncludesEveryAvailableSource() {
        let sourceIDs = [
            Self.sourceID(account: "a", mailbox: "one"),
            Self.sourceID(account: "b", mailbox: "two"),
        ]

        let profiles = MailProfileSelectionPolicy.resolvedProfiles(
            customProfiles: [],
            availableSourceIDs: sourceIDs
        )

        #expect(profiles.map(\.id) == [MailProfile.allMailboxesID])
        #expect(profiles.first?.sourceIDs == sourceIDs)
        #expect(profiles.first?.isSystem == true)
    }

    @Test("custom profiles retain unavailable sources and remove duplicate source ids")
    func customProfilesFilterUnavailableAndDuplicateSourceIDs() {
        let first = Self.sourceID(account: "a", mailbox: "one")
        let second = Self.sourceID(account: "b", mailbox: "two")
        let unavailable = Self.sourceID(account: "c", mailbox: "gone")
        let custom = MailProfile(
            id: "focused",
            name: " Focus ",
            sourceIDs: [first, first, unavailable, second]
        )

        let profiles = MailProfileSelectionPolicy.resolvedProfiles(
            customProfiles: [custom],
            availableSourceIDs: [first, second]
        )

        #expect(profiles.map(\.id) == [MailProfile.allMailboxesID, "focused"])
        #expect(profiles[1].name == "Focus")
        #expect(profiles[1].sourceIDs == [first, unavailable, second])
    }

    @Test("one source can belong to multiple custom profiles")
    func sourceCanBelongToMultipleProfiles() {
        let sourceID = Self.sourceID(account: "a", mailbox: "shared")
        let profiles = MailProfileSelectionPolicy.resolvedProfiles(
            customProfiles: [
                MailProfile(id: "work", name: "Work", sourceIDs: [sourceID]),
                MailProfile(id: "today", name: "Today", sourceIDs: [sourceID]),
            ],
            availableSourceIDs: [sourceID]
        )

        #expect(profiles[1].sourceIDs == [sourceID])
        #expect(profiles[2].sourceIDs == [sourceID])
    }

    @Test("empty profiles are removed but temporarily unavailable profiles remain")
    func customProfilesWithoutAvailableSourcesAreRemoved() {
        let unavailable = Self.sourceID(account: "a", mailbox: "gone")
        let profiles = MailProfileSelectionPolicy.resolvedProfiles(
            customProfiles: [
                MailProfile(id: "empty", name: "Empty", sourceIDs: []),
                MailProfile(id: "stale", name: "Stale", sourceIDs: [unavailable]),
            ],
            availableSourceIDs: []
        )

        #expect(profiles.map(\.id) == [MailProfile.allMailboxesID, "stale"])
    }

    @Test("visible sections are filtered by active custom profile")
    func visibleSectionsAreFilteredByActiveCustomProfile() {
        let first = Self.section(account: "a", mailbox: "one")
        let second = Self.section(account: "b", mailbox: "two")
        let custom = MailProfile(id: "focus", name: "Focus", sourceIDs: [second.id])
        let profiles = MailProfileSelectionPolicy.resolvedProfiles(
            customProfiles: [custom],
            availableSourceIDs: [first.id, second.id]
        )

        let visible = MailProfileSelectionPolicy.visibleSections(
            from: [first, second],
            activeProfileID: "focus",
            profiles: profiles
        )

        #expect(visible.map(\.id) == [second.id])
    }

    @Test("invalid active profile falls back to All Mailboxes")
    func invalidActiveProfileFallsBackToAllMailboxes() {
        let first = Self.section(account: "a", mailbox: "one")
        let profiles = MailProfileSelectionPolicy.resolvedProfiles(
            customProfiles: [],
            availableSourceIDs: [first.id]
        )

        let visible = MailProfileSelectionPolicy.visibleSections(
            from: [first],
            activeProfileID: "missing",
            profiles: profiles
        )

        #expect(visible.map(\.id) == [first.id])
        #expect(MailProfileSelectionPolicy.selectedProfileID("missing", profiles: profiles) == MailProfile.allMailboxesID)
    }

    @Test("profile storage round-trips custom profiles only")
    func profileStorageRoundTripsCustomProfilesOnly() {
        let sourceID = Self.sourceID(account: "a", mailbox: "one")
        let custom = MailProfile(id: "work", name: "Work", sourceIDs: [sourceID])
        let rawValue = MailProfileStorage.encode([
            .allMailboxes(sourceIDs: [sourceID]),
            custom,
        ])

        let decoded = MailProfileStorage.decode(rawValue)

        #expect(decoded == [custom])
    }

    @Test("custom profiles can be moved without crossing list boundaries")
    func customProfilesCanBeMovedWithoutCrossingListBoundaries() {
        let sourceID = Self.sourceID(account: "a", mailbox: "one")
        let profiles = [
            MailProfile(id: "focus", name: "Focus", sourceIDs: [sourceID]),
            MailProfile(id: "work", name: "Work", sourceIDs: [sourceID]),
            MailProfile(id: "personal", name: "Personal", sourceIDs: [sourceID]),
        ]

        let movedDown = MailProfileSelectionPolicy.moveCustomProfile(
            id: "focus",
            direction: .down,
            in: profiles
        )
        let movedUp = MailProfileSelectionPolicy.moveCustomProfile(
            id: "personal",
            direction: .up,
            in: profiles
        )
        let alreadyFirst = MailProfileSelectionPolicy.moveCustomProfile(
            id: "focus",
            direction: .up,
            in: profiles
        )
        let alreadyLast = MailProfileSelectionPolicy.moveCustomProfile(
            id: "personal",
            direction: .down,
            in: profiles
        )

        #expect(movedDown.map(\.id) == ["work", "focus", "personal"])
        #expect(movedUp.map(\.id) == ["focus", "personal", "work"])
        #expect(alreadyFirst == profiles)
        #expect(alreadyLast == profiles)
    }

    @Test("profile management sheet fits compact presentations")
    func profileManagementSheetFitsCompactPresentations() {
        let compactFrame = MailProfileManagementLayoutPolicy.sheetFrame(for: .compact)
        let regularFrame = MailProfileManagementLayoutPolicy.sheetFrame(for: .regular)

        #expect(compactFrame.minimumWidth == nil)
        #expect(compactFrame.maximumWidth == .infinity)
        #expect(compactFrame.minimumHeight == nil)
        #expect(regularFrame.minimumWidth == 520)
        #expect(regularFrame.minimumHeight == 420)
    }

    @Test("profile editor stacks before phone width can clip columns")
    func profileEditorStacksBeforePhoneWidthCanClipColumns() {
        #expect(MailProfileManagementLayoutPolicy.editorLayout(for: 393) == .stacked)
        #expect(MailProfileManagementLayoutPolicy.editorLayout(for: 640) == .columns)
    }

    private static func sourceID(account: String, mailbox: String) -> MailSourceID {
        MailSourceID(accountID: account, mailboxID: mailbox)
    }

    private static func section(account: String, mailbox: String) -> MailSourceSection {
        MailSourceSection(
            id: sourceID(account: account, mailbox: mailbox),
            account: BrevAccount(
                id: account,
                displayName: account,
                emailAddress: "\(account)@example.org"
            ),
            mailbox: Mailbox(
                id: mailbox,
                email: "\(mailbox)@example.org",
                displayName: mailbox,
                isPrimary: true
            ),
            folders: [
                Folder(id: "inbox", name: "Inbox", role: .inbox),
            ]
        )
    }
}
