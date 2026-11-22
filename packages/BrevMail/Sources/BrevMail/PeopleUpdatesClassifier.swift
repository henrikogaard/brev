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
import BrevDesign
import Foundation

/// The two-way inbox destination for local classification (#295, ADR-0035).
enum PeopleUpdatesBucket: String, Codable, Sendable, Hashable {
    case people
    case updates
}

/// Optional header/body metadata signals available locally without network calls.
struct PeopleUpdatesHeaderSignals: Equatable, Sendable {
    let hasListUnsubscribe: Bool
    let isBulkPrecedence: Bool

    init(hasListUnsubscribe: Bool = false, isBulkPrecedence: Bool = false) {
        self.hasListUnsubscribe = hasListUnsubscribe
        self.isBulkPrecedence = isBulkPrecedence
    }
}

/// Explainable reason why a message was placed in People or Updates.
enum PeopleUpdatesSignal: Equatable, Sendable {
    case senderOverride(PeopleUpdatesBucket)
    case listUnsubscribeHeader
    case bulkPrecedence
    case automatedSenderAddress
    case repliedToSender
    case transactionalOrNewsletterPattern(String)
    case directPerson
}

/// Result of deterministic local People/Updates classification.
struct PeopleUpdatesClassificationResult: Equatable, Sendable {
    let bucket: PeopleUpdatesBucket
    let signal: PeopleUpdatesSignal
}

/// Persists per-sender People/Updates overrides locally by normalized sender email (#295).
final class InboxSenderCategoryOverrideStore: Equatable {
    static let empty = InboxSenderCategoryOverrideStore(defaults: emptyDefaults)

    private static let key = "list.inboxSenderPeopleUpdatesOverrides.v1"
    private static let emptyDefaults = UserDefaults(suiteName: "InboxSenderCategoryOverrideStore.empty") ?? .standard
    private let defaults: UserDefaults
    private var cachedOverrides: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cachedOverrides = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    static func == (
        lhs: InboxSenderCategoryOverrideStore,
        rhs: InboxSenderCategoryOverrideStore
    ) -> Bool {
        lhs.defaults === rhs.defaults
    }

    /// Returns the remembered People/Updates override for `email`, or nil if unset.
    func bucket(forSenderEmail email: String) -> PeopleUpdatesBucket? {
        let normalized = Self.normalize(email)
        guard let raw = cachedOverrides[normalized] else { return nil }
        return PeopleUpdatesBucket(rawValue: raw)
    }

    /// Remembers `bucket` for every message from `email`.
    func set(_ bucket: PeopleUpdatesBucket, forSenderEmail email: String) {
        let normalized = Self.normalize(email)
        guard !normalized.isEmpty else { return }
        cachedOverrides[normalized] = bucket.rawValue
        defaults.set(cachedOverrides, forKey: Self.key)
    }

    /// Clears a saved sender override so heuristics apply again.
    func clear(senderEmail email: String) {
        let normalized = Self.normalize(email)
        cachedOverrides.removeValue(forKey: normalized)
        defaults.set(cachedOverrides, forKey: Self.key)
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Deterministic, local-only classifier for the People / Updates inbox split (ADR-0035 amendment).
enum PeopleUpdatesClassifier {
    private static let automatedLocalPartPatterns = [
        "noreply",
        "no-reply",
        "donotreply",
        "do-not-reply",
        "mailer-daemon",
        "notifications@",
        "notification@",
        "newsletter@",
        "newsletters@",
        "updates@",
        "notices@",
        "receipts@",
        "billing@",
        "marketing@",
        "digest@",
    ]

    private static let updateKeywords = [
        "unsubscribe",
        "newsletter",
        "weekly digest",
        "delivery digest",
        "receipt",
        "invoice",
        "order #",
        "order confirmation",
        "shipment",
        "security alert",
        "new sign-in",
        "verification code",
        "notification",
        "promotion",
        "discount",
        "coupon",
        "statement",
    ]

    static func classify(
        header: MessageHeader,
        signals: PeopleUpdatesHeaderSignals = PeopleUpdatesHeaderSignals(),
        repliedSenderEmails: Set<String> = [],
        senderOverrideStore: InboxSenderCategoryOverrideStore = InboxSenderCategoryOverrideStore()
    ) -> PeopleUpdatesClassificationResult {
        let senderEmail = header.from.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let override = senderOverrideStore.bucket(forSenderEmail: senderEmail) {
            return PeopleUpdatesClassificationResult(
                bucket: override,
                signal: .senderOverride(override)
            )
        }

        if signals.hasListUnsubscribe {
            return PeopleUpdatesClassificationResult(
                bucket: .updates,
                signal: .listUnsubscribeHeader
            )
        }

        if signals.isBulkPrecedence {
            return PeopleUpdatesClassificationResult(
                bucket: .updates,
                signal: .bulkPrecedence
            )
        }

        if automatedLocalPartPatterns.contains(where: { senderEmail.contains($0) }) {
            return PeopleUpdatesClassificationResult(
                bucket: .updates,
                signal: .automatedSenderAddress
            )
        }

        if !senderEmail.isEmpty, repliedSenderEmails.contains(senderEmail) {
            return PeopleUpdatesClassificationResult(
                bucket: .people,
                signal: .repliedToSender
            )
        }

        let searchableText = [
            header.subject,
            header.snippet,
            header.from.name ?? "",
            senderEmail,
        ]
        .joined(separator: " ")
        .lowercased()

        if let keyword = updateKeywords.first(where: { searchableText.contains($0) }) {
            return PeopleUpdatesClassificationResult(
                bucket: .updates,
                signal: .transactionalOrNewsletterPattern(keyword)
            )
        }

        return PeopleUpdatesClassificationResult(
            bucket: .people,
            signal: .directPerson
        )
    }
}

/// Live tab counts for the People / Updates / All pill bar (#295).
struct PeopleUpdatesCounts: Equatable, Sendable {
    let peopleCount: Int
    let updatesCount: Int
    let allCount: Int

    static func compute(
        headers: [MessageHeader],
        signalsByMessageID: [MessageHeader.ID: PeopleUpdatesHeaderSignals] = [:],
        repliedSenderEmails: Set<String> = [],
        senderOverrideStore: InboxSenderCategoryOverrideStore = InboxSenderCategoryOverrideStore()
    ) -> PeopleUpdatesCounts {
        var people = 0
        var updates = 0
        for header in headers {
            let bucket = PeopleUpdatesClassifier.classify(
                header: header,
                signals: signalsByMessageID[header.id] ?? PeopleUpdatesHeaderSignals(),
                repliedSenderEmails: repliedSenderEmails,
                senderOverrideStore: senderOverrideStore
            ).bucket
            switch bucket {
            case .people: people += 1
            case .updates: updates += 1
            }
        }
        return PeopleUpdatesCounts(
            peopleCount: people,
            updatesCount: updates,
            allCount: headers.count
        )
    }
}

/// One collapsed sender bundle in the Updates tab (#295).
struct UpdatesSenderBundle: Identifiable, Equatable, Sendable {
    let id: String
    let senderName: String
    let senderEmail: String
    let sourceID: MailSourceID?
    let headers: [MessageHeader]

    var latestHeader: MessageHeader { headers[0] }
    var unreadCount: Int { headers.filter { !$0.isRead }.count }
    var additionalCount: Int { max(0, headers.count - 1) }

    /// Compact summary matching `"Linear 2 · 2 new · 1 more from Linear"`.
    func summaryLine(locale: Locale = .current) -> String {
        var parts = ["\(senderName) \(headers.count)"]
        if unreadCount > 0 {
            parts.append(String(
                format: String(localized: "%lld new", bundle: .module, locale: locale),
                locale: locale,
                Int64(unreadCount)
            ))
        }
        if additionalCount > 0 {
            parts.append(String(
                format: String(localized: "%lld more from %@", bundle: .module, locale: locale),
                locale: locale,
                Int64(additionalCount),
                senderName
            ))
        }
        return parts.joined(separator: " · ")
    }
}

/// Groups Updates messages by normalized sender email, newest bundle first.
enum UpdatesSenderBundler {
    static func bundle(
        _ headers: [MessageHeader],
        sourceID: MailSourceID?
    ) -> [UpdatesSenderBundle] {
        var grouped: [String: [MessageHeader]] = [:]
        var orderedKeys: [String] = []

        let sorted = headers.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }

        for header in sorted {
            let key = header.from.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let bucketKey = key.isEmpty ? header.id : key
            if grouped[bucketKey] == nil {
                orderedKeys.append(bucketKey)
                grouped[bucketKey] = [header]
            } else {
                grouped[bucketKey, default: []].append(header)
            }
        }

        return orderedKeys.compactMap { key in
            guard let members = grouped[key], let latest = members.first else { return nil }
            let displayName = latest.from.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (displayName?.isEmpty == false ? displayName : nil) ?? latest.from.email
            return UpdatesSenderBundle(
                id: key,
                senderName: resolvedName,
                senderEmail: latest.from.email,
                sourceID: sourceID,
                headers: members
            )
        }
    }
}
