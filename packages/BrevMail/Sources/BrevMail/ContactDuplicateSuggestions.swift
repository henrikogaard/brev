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

/// Review-first duplicate suggestions for the contacts surface
/// (ADR-0072 #9).
///
/// A pure matcher over cached contacts: it scores name/email/phone
/// overlap and returns ranked candidates with human-readable reasons.
/// It never mutates anything — merging stays a human decision the UI
/// only ever offers as "open the candidate and compare".
public enum ContactDuplicateSuggestions {
    /// A suggested duplicate with the signals that ranked it.
    public struct Candidate: Sendable, Hashable, Identifiable {
        /// The cached contact that may duplicate the reviewed one.
        public let contact: PIMContact
        /// Why it was suggested, strongest signal first.
        public let reasons: [String]
        /// Total match score — ordering only, never a merge trigger.
        public let score: Int

        public var id: String { contact.id }

        public init(contact: PIMContact, reasons: [String], score: Int) {
            self.contact = contact
            self.reasons = reasons
            self.score = score
        }
    }

    /// Ranked suggestions for a contact within a cached set. The
    /// contact is matched by stable signals: identical emails, phone
    /// numbers compared on digits only, and normalized name equality.
    /// Self-matches and zero-signal records are excluded.
    public static func candidates(
        for contact: PIMContact,
        in all: [PIMContact],
        limit: Int = 5
    ) -> [Candidate] {
        all
            .filter { $0.id != contact.id }
            .compactMap { score(contact, against: $0) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.contact.displayName != rhs.contact.displayName {
                    return lhs.contact.displayName
                        .localizedStandardCompare(rhs.contact.displayName)
                        == .orderedAscending
                }
                return lhs.contact.id < rhs.contact.id
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Scores one pair; nil means no shared signal — not a suggestion.
    private static func score(
        _ contact: PIMContact,
        against candidate: PIMContact
    ) -> Candidate? {
        var score = 0
        var reasons: [String] = []
        if sharedEmails(contact, candidate) {
            score += 100
            reasons.append(
                String(localized: "Same email address", bundle: .module)
            )
        }
        if sharedPhones(contact, candidate) {
            score += 80
            reasons.append(
                String(localized: "Same phone number", bundle: .module)
            )
        }
        if sameName(contact, candidate) {
            score += 60
            reasons.append(
                String(localized: "Same name", bundle: .module)
            )
        }
        guard score > 0 else { return nil }
        return Candidate(contact: candidate, reasons: reasons, score: score)
    }

    private static func sharedEmails(
        _ lhs: PIMContact,
        _ rhs: PIMContact
    ) -> Bool {
        let left = Set(
            lhs.emails.map { normalizeEmail($0.value) }.filter { !$0.isEmpty }
        )
        let right = Set(
            rhs.emails.map { normalizeEmail($0.value) }.filter { !$0.isEmpty }
        )
        return !left.isDisjoint(with: right)
    }

    private static func sharedPhones(
        _ lhs: PIMContact,
        _ rhs: PIMContact
    ) -> Bool {
        let left = Set(
            lhs.phones.compactMap { normalizePhone($0.value) }
        )
        let right = Set(
            rhs.phones.compactMap { normalizePhone($0.value) }
        )
        return !left.isDisjoint(with: right)
    }

    /// Full-name equality after case/diacritic folding — the display
    /// name and the joined split names each count, so a
    /// display-name-only record still matches a split-name-only twin.
    private static func sameName(
        _ lhs: PIMContact,
        _ rhs: PIMContact
    ) -> Bool {
        nameForms(lhs).contains { left in
            !left.isEmpty && nameForms(rhs).contains(left)
        }
    }

    private static func nameForms(_ contact: PIMContact) -> [String] {
        let split = [contact.givenName, contact.familyName]
            .compactMap { $0.map(normalizeName) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [normalizeName(contact.displayName), split]
            .filter { !$0.isEmpty }
    }

    private static func normalizeEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Digits only — formatting and punctuation never decide equality.
    /// A leading "+" or "00" international prefix is stripped first.
    private static func normalizePhone(_ value: String) -> String? {
        var digits = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        digits = digits.hasPrefix("+")
            ? String(digits.dropFirst())
            : digits.hasPrefix("00") ? String(digits.dropFirst(2)) : digits
        digits = digits.filter { $0.isNumber }
        // Fewer than 5 digits never identifies a phone number.
        return digits.count >= 5 ? digits : nil
    }

    private static func normalizeName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            )
    }
}
