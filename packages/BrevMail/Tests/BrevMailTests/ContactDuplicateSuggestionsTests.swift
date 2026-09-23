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

/// Duplicate-suggestion coverage (ADR-0072 #9): scoring and ordering by
/// shared signal, normalizations, the review-only contract — nothing is
/// ever merged or mutated.
@Suite("ContactDuplicateSuggestions")
struct ContactDuplicateSuggestionsTests {
    private static func contact(
        id: String,
        displayName: String = "Person",
        givenName: String? = nil,
        familyName: String? = nil,
        emails: [String] = [],
        phones: [String] = []
    ) -> PIMContact {
        PIMContact(
            id: id,
            sourceID: "s1",
            providerItemKey: id,
            displayName: displayName,
            givenName: givenName,
            familyName: familyName,
            emails: emails.map { PIMContactField(value: $0) },
            phones: phones.map { PIMContactField(value: $0) }
        )
    }

    @Test("Stronger shared signals rank above weaker ones")
    func ranking() {
        let subject = Self.contact(
            id: "me",
            displayName: "Ada Lovelace",
            emails: ["ada@example.com"],
            phones: ["+47 555 0100"]
        )
        let all = [
            // All three signals — ranks first.
            Self.contact(
                id: "triple",
                displayName: "Ada Lovelace",
                emails: ["ADA@example.com"],
                phones: ["0047 555 01 00"]
            ),
            // Email only — ranks second.
            Self.contact(
                id: "email",
                displayName: "Different Name",
                emails: ["ada@example.com"]
            ),
            // Name only — ranks third.
            Self.contact(
                id: "name",
                displayName: "ada lovelace"
            ),
            // No shared signal — excluded.
            Self.contact(
                id: "other",
                displayName: "Grace Hopper",
                emails: ["grace@example.com"]
            ),
            subject,
        ]

        let found = ContactDuplicateSuggestions.candidates(
            for: subject,
            in: all
        )

        #expect(found.map(\.id) == ["triple", "email", "name"])
        // Reasons travel with the suggestion, strongest signal first.
        #expect(found[0].reasons.count == 3)
        #expect(found[1].reasons == [
            String(localized: "Same email address", bundle: .module),
        ])
    }

    @Test("Phone formatting never decides equality")
    func phoneNormalization() {
        let subject = Self.contact(
            id: "me",
            displayName: "Subject",
            phones: ["+47 555 0100"]
        )
        let candidates = ContactDuplicateSuggestions.candidates(
            for: subject,
            in: [
                Self.contact(
                    id: "intl",
                    displayName: "Alpha",
                    phones: ["0047 555-01-00"]
                ),
                Self.contact(
                    id: "local",
                    displayName: "Beta",
                    phones: ["555 0100"]
                ),
                Self.contact(
                    id: "tooShort",
                    displayName: "Gamma",
                    phones: ["0100"]
                ),
            ]
        )
        // "+" and "00" prefixes fold; the local dialling form does not —
        // it is a different set of digits.
        #expect(candidates.map(\.id) == ["intl"])
    }

    @Test("Split names match display names and folding ignores case")
    func nameMatching() {
        let subject = Self.contact(
            id: "me",
            displayName: "Émile Zola"
        )
        let candidates = ContactDuplicateSuggestions.candidates(
            for: subject,
            in: [
                // Split-name equivalent.
                Self.contact(
                    id: "split",
                    displayName: "Someone Else",
                    givenName: "Emile",
                    familyName: "Zola"
                ),
                // Diacritic-folded display-name equality.
                Self.contact(id: "folded", displayName: "emile zola"),
            ]
        )
        #expect(candidates.map(\.id).sorted() == ["folded", "split"])
    }

    @Test("Suggestions never mutate the reviewed set")
    func neverMutates() {
        let subject = Self.contact(
            id: "me",
            displayName: "Ada",
            emails: ["ada@example.com"]
        )
        let all = [
            subject,
            Self.contact(
                id: "dup",
                displayName: "Ada",
                emails: ["ada@example.com"]
            ),
        ]
        let before = all

        let found = ContactDuplicateSuggestions.candidates(
            for: subject,
            in: all
        )

        // Pure scoring: the inputs are untouched — review stays a
        // human-only decision, nothing is merged or rewritten.
        #expect(all == before)
        #expect(found.first?.id == "dup")
        #expect(found.first?.contact.emails.first?.value == "ada@example.com")
    }

    @Test("The limit caps the candidate list")
    func limitRespected() {
        let subject = Self.contact(
            id: "me",
            emails: ["shared@example.com"]
        )
        let pool = (0 ..< 8).map {
            Self.contact(id: "c\($0)", emails: ["shared@example.com"])
        }
        #expect(
            ContactDuplicateSuggestions
                .candidates(for: subject, in: pool, limit: 3).count == 3
        )
        #expect(
            ContactDuplicateSuggestions
                .candidates(for: subject, in: pool).count == 5
        )
    }
}
