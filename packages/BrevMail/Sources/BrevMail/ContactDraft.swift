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
import Foundation

/// Editable form state for the contact editor (ADR-0072 #9).
///
/// The draft owns every field the editor renders and converts to and
/// from PIMContact. Provider identity fields (uid, providerItemKey,
/// providerVersion, rawPayload) ride along untouched so an edit
/// round-trips the record the provider owns while the user-facing
/// fields carry the edits. Photos upload through the draft's
/// photoData — picked bytes replace, the photoRemoved flag drops, and
/// untouched state passes through unchanged.
public struct ContactDraft: Sendable, Hashable {
    public var givenName = ""
    public var familyName = ""
    public var nickname = ""
    public var organization = ""
    public var jobTitle = ""
    public var note = ""
    public var emails: [PIMContactField] = []
    public var phones: [PIMContactField] = []
    public var addresses: [PIMContactAddress] = []
    /// Labeled dates (birthday, anniversary, custom).
    public var dates: [PIMContactDate] = []
    /// Labeled URL fields.
    public var urls: [PIMContactField] = []
    /// Group memberships: Google contactGroupResourceNames or CardDAV
    /// CATEGORIES values, edited per provider in the editor.
    public var groupKeys: [String] = []
    /// Provider photo reference — kept so an untouched photo survives.
    public var photoURL: String?
    /// Photo bytes to upload — picked in the editor, nil means either
    /// "keep the existing photo" or "no photo" per photoRemoved.
    public var photoData: Data?
    /// Explicit photo removal — wins over photoURL/photoData.
    public var photoRemoved = false
    /// The write target: a CardDAV collection ID for DAV sources, or
    /// the Google account-wide sentinel for Google sources.
    public var targetID: String?

    // Provider identity carried through edits; always nil on create.
    var uid: String?
    var providerItemKey: String?
    var providerVersion: String?
    var rawPayload: String?
    var providerUpdatedAt: Date?
    /// The collection the edited contact belongs to, for move
    /// detection; Google contacts leave this nil (groups carry
    /// membership instead).
    var originalCollectionID: PIMCollection.ID?
    /// The display name the provider had — kept as the fallback when
    /// the user clears every name field.
    var originalDisplayName = ""

    /// A blank draft for a new contact.
    public init() {}

    /// A draft pre-filled from a cached contact for editing.
    public init(contact: PIMContact) {
        givenName = contact.givenName ?? ""
        familyName = contact.familyName ?? ""
        nickname = contact.nickname ?? ""
        organization = contact.organization ?? ""
        jobTitle = contact.jobTitle ?? ""
        note = contact.note ?? ""
        emails = contact.emails
        phones = contact.phones
        addresses = contact.addresses
        dates = contact.dates
        urls = contact.urls
        groupKeys = contact.groupKeys
        photoURL = contact.photoURL
        photoData = contact.photoData
        targetID = contact.collectionID
        originalCollectionID = contact.collectionID
        uid = contact.uid
        providerItemKey = contact.providerItemKey
        providerVersion = contact.providerVersion
        rawPayload = contact.rawPayload
        providerUpdatedAt = contact.providerUpdatedAt
        originalDisplayName = contact.displayName
    }

    /// The display name the record will carry: the split names joined,
    /// else the nickname, else the first email, else the provider's
    /// original display name.
    public var resolvedDisplayName: String {
        let joined = [givenName, familyName]
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !joined.isEmpty { return joined }
        let trimmedNickname = nickname.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedNickname.isEmpty { return trimmedNickname }
        if let email = emails.first?.value
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !email.isEmpty {
            return email
        }
        return originalDisplayName
    }

    /// Whether the draft can save: a resolvable name plus a target.
    public var isValid: Bool {
        !resolvedDisplayName.isEmpty && targetID != nil
    }

    /// Whether this draft edits an existing cached contact.
    public var isEditing: Bool { providerItemKey != nil }

    /// Builds the provider-facing contact record. Identity fields come
    /// from the edited contact; on create they stay nil so the write
    /// service assigns them.
    public func makeContact(
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID?
    ) -> PIMContact {
        let itemKey = providerItemKey ?? "draft"
        return PIMContact(
            id: PIMContact.makeID(
                sourceID: sourceID,
                providerItemKey: itemKey
            ),
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: itemKey,
            providerVersion: providerVersion,
            uid: uid,
            displayName: resolvedDisplayName,
            givenName: trimmedOrNil(givenName),
            familyName: trimmedOrNil(familyName),
            nickname: trimmedOrNil(nickname),
            organization: trimmedOrNil(organization),
            jobTitle: trimmedOrNil(jobTitle),
            note: trimmedOrNil(note),
            emails: cleaned(emails),
            phones: cleaned(phones),
            addresses: addresses.filter { !$0.isEmpty },
            dates: cleaned(dates),
            urls: cleaned(urls),
            photoURL: photoRemoved ? nil : photoURL,
            photoData: photoRemoved ? nil : photoData,
            groupKeys: groupKeys,
            rawPayload: rawPayload,
            providerUpdatedAt: providerUpdatedAt
        )
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleaned(
        _ fields: [PIMContactField]
    ) -> [PIMContactField] {
        fields.compactMap { field in
            let value = field.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !value.isEmpty else { return nil }
            let label = field.label?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return PIMContactField(
                label: label?.isEmpty == false ? label : nil,
                value: value
            )
        }
    }

    /// Drops dates with an impossible month/day and blanks the label
    /// whitespace; the pickers already constrain the day range.
    private func cleaned(
        _ dates: [PIMContactDate]
    ) -> [PIMContactDate] {
        dates.compactMap { date in
            guard (1 ... 12).contains(date.month),
                  (1 ... 31).contains(date.day)
            else { return nil }
            let label = date.label?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return PIMContactDate(
                label: label?.isEmpty == false ? label : nil,
                year: date.year,
                month: date.month,
                day: date.day
            )
        }
    }
}
