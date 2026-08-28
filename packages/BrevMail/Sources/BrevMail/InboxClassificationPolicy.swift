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
import BrevSettings
import Foundation

struct InboxClassificationResult: Equatable, Sendable {
    let category: InboxCategory
    let reason: InboxClassificationReason
}

enum InboxClassificationReason: Equatable, Sendable {
    case manualOverride
    case matchedKeyword(String)
    case directMessage
    case fallback
}

final class InboxCategoryOverrideStore: Equatable {
    static let empty = InboxCategoryOverrideStore(defaults: emptyDefaults)

    private static let key = "list.inboxCategoryOverrides"
    private static let emptyDefaults = UserDefaults(suiteName: "InboxCategoryOverrideStore.empty") ?? .standard
    private let defaults: UserDefaults
    /// Keep the decoded override map in memory for the lifetime of a store.
    /// Classification runs once per visible row, so consulting UserDefaults
    /// from `category(for:)` made a mailbox refresh perform one plist lookup
    /// per row.
    private var cachedOverrides: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cachedOverrides = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    static func == (
        lhs: InboxCategoryOverrideStore,
        rhs: InboxCategoryOverrideStore
    ) -> Bool {
        lhs.defaults === rhs.defaults
    }

    func category(for messageID: SourceMessageID) -> InboxCategory? {
        guard let rawCategory = cachedOverrides[Self.storageKey(for: messageID)] else { return nil }
        return InboxCategory(rawValue: rawCategory)
    }

    func set(_ category: InboxCategory, for messageID: SourceMessageID) {
        cachedOverrides[Self.storageKey(for: messageID)] = category.rawValue
        defaults.set(cachedOverrides, forKey: Self.key)
    }

    func clear(_ messageID: SourceMessageID) {
        cachedOverrides.removeValue(forKey: Self.storageKey(for: messageID))
        defaults.set(cachedOverrides, forKey: Self.key)
    }

    private static func storageKey(for messageID: SourceMessageID) -> String {
        "\(messageID.sourceID.accountID)|\(messageID.sourceID.mailboxID)|\(messageID.messageID)"
    }
}

enum InboxClassificationPolicy {
    static func classification(
        for header: MessageHeader,
        sourceID: MailSourceID?,
        overrideStore: InboxCategoryOverrideStore = InboxCategoryOverrideStore()
    ) -> InboxClassificationResult {
        if let sourceID,
           let override = overrideStore.category(
               for: SourceMessageID(sourceID: sourceID, messageID: header.id)
           ) {
            return InboxClassificationResult(category: override, reason: .manualOverride)
        }

        let searchableText = [
            header.subject,
            header.snippet,
            header.from.name ?? "",
            header.from.email
        ]
        .joined(separator: " ")
        .lowercased()

        if let keyword = firstMatch(in: searchableText, keywords: transactionKeywords) {
            return InboxClassificationResult(category: .transactions, reason: .matchedKeyword(keyword))
        }
        if let keyword = firstMatch(in: searchableText, keywords: promotionKeywords) {
            return InboxClassificationResult(category: .promotions, reason: .matchedKeyword(keyword))
        }
        if let keyword = firstMatch(in: searchableText, keywords: updateKeywords) {
            return InboxClassificationResult(category: .updates, reason: .matchedKeyword(keyword))
        }
        if isLikelyDirectMessage(header) {
            return InboxClassificationResult(category: .primary, reason: .directMessage)
        }
        return InboxClassificationResult(category: .other, reason: .fallback)
    }

    private static let transactionKeywords = [
        "invoice",
        "receipt",
        "order",
        "payment",
        "paid",
        "shipment",
        "delivery",
        "booking",
        "statement",
        "subscription"
    ]

    private static let promotionKeywords = [
        "unsubscribe",
        "newsletter",
        "offer",
        "sale",
        "discount",
        "deal",
        "coupon",
        "promotion"
    ]

    private static let updateKeywords = [
        "security alert",
        "notification",
        "update",
        "digest",
        "comment",
        "mentioned",
        "noreply",
        "no-reply"
    ]

    private static func firstMatch(
        in text: String,
        keywords: [String]
    ) -> String? {
        keywords.first { text.contains($0) }
    }

    private static func isLikelyDirectMessage(_ header: MessageHeader) -> Bool {
        let email = header.from.email.lowercased()
        return !email.contains("noreply")
            && !email.contains("no-reply")
            && !email.contains("newsletter")
            && !email.contains("marketing")
    }
}

enum InboxClassificationVisibilityPolicy {
    static func headers(
        _ headers: [MessageHeader],
        sourceID: MailSourceID?,
        selectedCategory: InboxCategory,
        settings: InboxClassificationSettings,
        overrideStore: InboxCategoryOverrideStore = InboxCategoryOverrideStore()
    ) -> [MessageHeader] {
        guard settings.mode == .categories, selectedCategory != .all else {
            return headers
        }
        return headers.filter { header in
            InboxClassificationPolicy.classification(
                for: header,
                sourceID: sourceID,
                overrideStore: overrideStore
            ).category == selectedCategory
        }
    }

    static func items(
        _ items: [UnifiedInboxItem],
        selectedCategory: InboxCategory,
        settings: InboxClassificationSettings,
        overrideStore: InboxCategoryOverrideStore = InboxCategoryOverrideStore()
    ) -> [UnifiedInboxItem] {
        guard settings.mode == .categories, selectedCategory != .all else {
            return items
        }
        return items.filter { item in
            InboxClassificationPolicy.classification(
                for: item.header,
                sourceID: item.sourceID,
                overrideStore: overrideStore
            ).category == selectedCategory
        }
    }
}
