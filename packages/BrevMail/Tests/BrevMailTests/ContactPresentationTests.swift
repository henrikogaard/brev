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

/// Presentation-helper coverage for the Contacts surface (ADR-0072 #8):
/// monograms, subtitles, field labels, address lines, letter bucketing,
/// and the local search corpus.
@Suite("ContactPresentation")
struct ContactPresentationTests {
    private static func contact(
        displayName: String = "Ada Lovelace",
        givenName: String? = nil,
        familyName: String? = nil,
        nickname: String? = nil,
        organization: String? = nil,
        jobTitle: String? = nil,
        emails: [PIMContactField] = [],
        phones: [PIMContactField] = []
    ) -> PIMContact {
        PIMContact(
            id: UUID().uuidString,
            sourceID: "s",
            providerItemKey: "k",
            displayName: displayName,
            givenName: givenName,
            familyName: familyName,
            nickname: nickname,
            organization: organization,
            jobTitle: jobTitle,
            emails: emails,
            phones: phones,
            syncedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    // MARK: - Initials

    @Test("initials prefer given + family name letters")
    func initialsFromNames() {
        let contact = Self.contact(
            givenName: "Ada",
            familyName: "Lovelace"
        )
        #expect(ContactPresentation.initials(for: contact) == "AL")
    }

    @Test("initials fall back to the display name's leading words")
    func initialsFromDisplayName() {
        let contact = Self.contact(displayName: "Grace Brewster Hopper")
        #expect(ContactPresentation.initials(for: contact) == "GB")
    }

    @Test("a single-word display name yields one letter")
    func initialsSingleWord() {
        let contact = Self.contact(displayName: "Prince")
        #expect(ContactPresentation.initials(for: contact) == "P")
    }

    // MARK: - Subtitle

    @Test("subtitle joins job title and organization")
    func subtitleJobAndOrg() {
        let contact = Self.contact(
            organization: "Ogard Labs",
            jobTitle: "Engineer"
        )
        #expect(
            ContactPresentation.subtitle(for: contact)
                == "Engineer · Ogard Labs"
        )
    }

    @Test("subtitle falls back to the first email, then phone")
    func subtitleFallbacks() {
        let withEmail = Self.contact(
            emails: [PIMContactField(value: "ada@example.com")]
        )
        #expect(
            ContactPresentation.subtitle(for: withEmail)
                == "ada@example.com"
        )

        let withPhone = Self.contact(
            phones: [PIMContactField(value: "+47 999")]
        )
        #expect(
            ContactPresentation.subtitle(for: withPhone) == "+47 999"
        )

        #expect(ContactPresentation.subtitle(for: Self.contact()) == nil)
    }

    // MARK: - Field labels

    @Test("vCard-style labels normalize to title case")
    func fieldLabelNormalization() {
        #expect(
            ContactPresentation.fieldLabel("WORK", fallback: "Email")
                == "Work"
        )
        #expect(
            ContactPresentation.fieldLabel("home", fallback: "Email")
                == "Home"
        )
        #expect(
            ContactPresentation.fieldLabel(nil, fallback: "Email")
                == "Email"
        )
        #expect(
            ContactPresentation.fieldLabel("", fallback: "Email")
                == "Email"
        )
    }

    // MARK: - Addresses

    @Test("address text joins the present components")
    func addressText() {
        let address = PIMContactAddress(
            street: "1 Infinite Loop",
            city: "Cupertino",
            country: "USA"
        )
        #expect(
            ContactPresentation.addressText(for: address)
                == "1 Infinite Loop, Cupertino, USA"
        )
        #expect(
            ContactPresentation.addressText(for: PIMContactAddress())
                == ""
        )
    }

    // MARK: - Section keys

    @Test("section key is the uppercased first letter, or #")
    func sectionKey() {
        #expect(
            ContactPresentation.sectionKey(
                for: Self.contact(displayName: "ada")
            ) == "A"
        )
        #expect(
            ContactPresentation.sectionKey(
                for: Self.contact(displayName: "3M")
            ) == "#"
        )
        #expect(
            ContactPresentation.sectionKey(
                for: Self.contact(displayName: "")
            ) == "#"
        )
    }

    // MARK: - Search

    @Test("search is case- and diacritic-insensitive across cached fields")
    func matches() {
        let contact = Self.contact(
            displayName: "Søren Kierkegaard",
            organization: "Ogard Labs",
            emails: [PIMContactField(value: "soren@example.com")]
        )

        #expect(ContactPresentation.matches(contact, query: "kierkegaard"))
        #expect(ContactPresentation.matches(contact, query: "SOREN"))
        #expect(ContactPresentation.matches(contact, query: "ogard"))
        #expect(ContactPresentation.matches(contact, query: "soren@"))
        #expect(ContactPresentation.matches(contact, query: "  "))
        #expect(!ContactPresentation.matches(contact, query: "nobody"))
    }

    @Test("diacritics fold so ø matches o")
    func diacriticFolding() {
        let contact = Self.contact(displayName: "Søren")
        #expect(ContactPresentation.matches(contact, query: "soren"))
    }
}
