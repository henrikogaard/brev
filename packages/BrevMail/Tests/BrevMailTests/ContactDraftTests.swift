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

import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

/// Draft mapping coverage for the contact editor (ADR-0072 #9):
/// contact-to-form round-trips, display-name resolution, validation,
/// and provider-identity preservation.
@Suite("ContactDraft")
struct ContactDraftTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static func contact() -> PIMContact {
        PIMContact(
            id: "c1",
            sourceID: "s1",
            collectionID: "book1",
            providerItemKey: "https://dav.example.com/c/c1.vcf",
            providerVersion: "\"v2\"",
            uid: "uid-c1@brev",
            displayName: "Henrik Ogard",
            givenName: "Henrik",
            familyName: "Ogard",
            nickname: "HK",
            organization: "Ogard Labs",
            jobTitle: "Founder",
            note: "Met at WWDC",
            emails: [
                PIMContactField(label: "work", value: "h@example.com"),
            ],
            phones: [PIMContactField(label: "cell", value: "+47 999")],
            addresses: [PIMContactAddress(
                label: "home",
                street: "Gate 1",
                city: "Oslo"
            )],
            photoURL: "https://example.com/p.jpg",
            groupKeys: ["Friends"],
            rawPayload: "BEGIN:VCARD\nVERSION:3.0\nEND:VCARD",
            providerUpdatedAt: fixedNow,
            syncedAt: fixedNow
        )
    }

    @Test("init(contact:) maps every editable field")
    func initFromContact() {
        let draft = ContactDraft(contact: Self.contact())

        #expect(draft.isEditing)
        #expect(draft.givenName == "Henrik")
        #expect(draft.familyName == "Ogard")
        #expect(draft.nickname == "HK")
        #expect(draft.organization == "Ogard Labs")
        #expect(draft.jobTitle == "Founder")
        #expect(draft.note == "Met at WWDC")
        #expect(draft.emails.count == 1)
        #expect(draft.phones.count == 1)
        #expect(draft.addresses.count == 1)
        #expect(draft.groupKeys == ["Friends"])
        #expect(draft.photoURL == "https://example.com/p.jpg")
        #expect(draft.targetID == "book1")
    }

    @Test("makeContact preserves provider identity and cleans fields")
    func makeContactPreservesIdentity() {
        var draft = ContactDraft(contact: Self.contact())
        draft.emails.append(
            PIMContactField(label: "  ", value: "  spaced@example.com  ")
        )
        draft.emails.append(PIMContactField(label: nil, value: ""))

        let contact = draft.makeContact(
            sourceID: "s1",
            collectionID: "book1"
        )

        #expect(contact.providerItemKey == "https://dav.example.com/c/c1.vcf")
        #expect(contact.providerVersion == "\"v2\"")
        #expect(contact.uid == "uid-c1@brev")
        #expect(contact.rawPayload != nil)
        #expect(contact.emails.count == 2)
        // Blank labels normalize to nil; empty values drop out.
        #expect(contact.emails[1].label == nil)
        #expect(contact.emails[1].value == "spaced@example.com")
    }

    @Test("resolvedDisplayName falls back through name, nickname, email")
    func displayNameResolution() {
        var draft = ContactDraft(contact: Self.contact())
        #expect(draft.resolvedDisplayName == "Henrik Ogard")

        draft.givenName = ""
        draft.familyName = ""
        #expect(draft.resolvedDisplayName == "HK")

        draft.nickname = ""
        #expect(draft.resolvedDisplayName == "h@example.com")

        draft.emails = []
        // Nothing left — the provider's original name is kept.
        #expect(draft.resolvedDisplayName == "Henrik Ogard")
    }

    @Test("isValid requires a resolvable name and a target")
    func validation() {
        var draft = ContactDraft()
        #expect(!draft.isValid)

        draft.givenName = "Ana"
        #expect(!draft.isValid)

        draft.targetID = "book1"
        #expect(draft.isValid)
    }

    @Test("a create draft produces a record without provider identity")
    func createDraft() {
        var draft = ContactDraft()
        draft.givenName = "Ana"
        draft.familyName = "Lind"
        draft.targetID = "book1"

        let contact = draft.makeContact(
            sourceID: "s1",
            collectionID: "book1"
        )

        #expect(!draft.isEditing)
        #expect(contact.providerItemKey == "draft")
        #expect(contact.uid == nil)
        #expect(contact.displayName == "Ana Lind")
    }
}
