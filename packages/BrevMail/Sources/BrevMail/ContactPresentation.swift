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

/// Presentation strings for cached contacts (ADR-0072 browsing).
///
/// Pure functions over `PIMContact` so the list and detail surfaces share
/// one formatting contract and stay testable without rendering a view.
public enum ContactPresentation {
    /// Up-to-two-letter monogram for the avatar fallback: first letters
    /// of given + family name, else the display name's leading words.
    public static func initials(for contact: PIMContact) -> String {
        let letters = [contact.givenName, contact.familyName]
            .compactMap { $0?.first }
            .map { String($0).uppercased() }
        if !letters.isEmpty {
            return letters.joined()
        }
        let words = contact.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
        if !words.isEmpty {
            return words.joined()
        }
        return String(localized: "?", bundle: .module)
    }

    /// Secondary line under a contact's name: job title + organization,
    /// else the first email or phone so the row is never bare.
    public static func subtitle(for contact: PIMContact) -> String? {
        var parts: [String] = []
        if let jobTitle = contact.jobTitle, !jobTitle.isEmpty {
            parts.append(jobTitle)
        }
        if let organization = contact.organization, !organization.isEmpty {
            parts.append(organization)
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        if let email = contact.emails.first?.value, !email.isEmpty {
            return email
        }
        if let phone = contact.phones.first?.value, !phone.isEmpty {
            return phone
        }
        return nil
    }

    /// Row label for a labeled field — the provider's label when present,
    /// else a generic one.
    public static func fieldLabel(
        _ label: String?,
        fallback: String
    ) -> String {
        guard let label, !label.isEmpty else { return fallback }
        // vCard labels arrive like "WORK"/"HOME"/"item1"; People labels
        // arrive lowercased. Capitalize single-word labels for display.
        if label.allSatisfy({ !$0.isLowercase }) || label == label.lowercased() {
            return label.prefix(1).uppercased() + label.dropFirst().lowercased()
        }
        return label
    }

    /// Display text for a labeled date — month + day only when the
    /// date carries no year.
    public static func dateText(for date: PIMContactDate) -> String {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        guard let value = Calendar.current.date(from: components) else {
            return ""
        }
        if date.year == nil {
            return value.formatted(.dateTime.month().day())
        }
        return value.formatted(.dateTime.month().day().year())
    }

    /// One-line postal address for list/detail display.
    public static func addressText(for address: PIMContactAddress) -> String {
        [
            address.street,
            address.city,
            address.region,
            address.postalCode,
            address.country,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    /// Alphabetical section key for a contact — the display name's first
    /// letter uppercased, or "#" for contacts starting with a non-letter.
    public static func sectionKey(for contact: PIMContact) -> String {
        guard let first = contact.displayName.first else { return "#" }
        let letter = String(first).uppercased()
        return letter.range(of: "[A-Z]", options: .regularExpression) != nil
            ? letter
            : "#"
    }

    /// The local-only search corpus — names, nickname, organization,
    /// title, emails, phones. Provider payloads are never searched here.
    public static func searchableText(of contact: PIMContact) -> String {
        var fields = [contact.displayName]
        if let given = contact.givenName { fields.append(given) }
        if let family = contact.familyName { fields.append(family) }
        if let nickname = contact.nickname { fields.append(nickname) }
        if let organization = contact.organization {
            fields.append(organization)
        }
        if let jobTitle = contact.jobTitle { fields.append(jobTitle) }
        fields.append(contentsOf: contact.emails.map(\.value))
        fields.append(contentsOf: contact.phones.map(\.value))
        fields.append(contentsOf: contact.urls.map(\.value))
        return fields.joined(separator: "\n")
    }

    /// Whether a contact matches a trimmed, case- and
    /// diacritic-insensitive query across the cached fields.
    public static func matches(_ contact: PIMContact, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return searchableText(of: contact).range(
            of: trimmed,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}
