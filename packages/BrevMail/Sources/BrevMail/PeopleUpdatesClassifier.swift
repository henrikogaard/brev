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
import SwiftUI

/// Groups People/Updates observers into a dedicated modifier so `MessageListView`
/// stays well within SwiftUI's expression type-check budget (#295).
struct PeopleUpdatesObserverModifier: ViewModifier {
    let activeTab: InboxSplitTab
    let signalRefreshKey: String
    let selectedMessageID: MessageHeader.ID?
    let onOverridesChanged: () -> Void
    let onTabChanged: () -> Void
    let onMessageOpened: (MessageHeader.ID) -> Void
    let onRefreshSignals: () async -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .brevPeopleUpdatesOverridesDidChange)) { _ in
                onOverridesChanged()
            }
            .onChange(of: activeTab) { _, _ in
                onTabChanged()
            }
            .onChange(of: selectedMessageID) { _, openedID in
                if let openedID {
                    onMessageOpened(openedID)
                }
            }
            .task(id: signalRefreshKey) {
                await onRefreshSignals()
            }
    }
}

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

extension Notification.Name {
    /// Posted whenever a People/Updates sender override changes so every open
    /// window refreshes its classification without overwriting sibling edits.
    static let brevPeopleUpdatesOverridesDidChange = Notification.Name(
        "brev.peopleUpdatesOverridesDidChange"
    )
}

/// Persists per-sender People/Updates overrides locally by normalized sender email (#295).
final class InboxSenderCategoryOverrideStore: Equatable, @unchecked Sendable {
    static let shared = InboxSenderCategoryOverrideStore()
    static let empty = InboxSenderCategoryOverrideStore(defaults: emptyDefaults)

    private static let key = "list.inboxSenderPeopleUpdatesOverrides.v1"
    private static let emptyDefaults = UserDefaults(suiteName: "InboxSenderCategoryOverrideStore.empty") ?? .standard
    private static let defaultsLock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        guard !normalized.isEmpty else { return nil }
        return Self.defaultsLock.withLock {
            let current = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
            guard let raw = current[normalized] else { return nil }
            return PeopleUpdatesBucket(rawValue: raw)
        }
    }

    /// Remembers `bucket` for every message from `email`, merging with any
    /// concurrent writes from other windows.
    func set(_ bucket: PeopleUpdatesBucket, forSenderEmail email: String) {
        let normalized = Self.normalize(email)
        guard !normalized.isEmpty else { return }
        Self.defaultsLock.withLock {
            var current = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
            current[normalized] = bucket.rawValue
            defaults.set(current, forKey: Self.key)
        }
        NotificationCenter.default.post(name: .brevPeopleUpdatesOverridesDidChange, object: nil)
    }

    /// Clears a saved sender override so heuristics apply again.
    func clear(senderEmail email: String) {
        let normalized = Self.normalize(email)
        guard !normalized.isEmpty else { return }
        Self.defaultsLock.withLock {
            var current = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
            current.removeValue(forKey: normalized)
            defaults.set(current, forKey: Self.key)
        }
        NotificationCenter.default.post(name: .brevPeopleUpdatesOverridesDidChange, object: nil)
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Determines whether the message list renders date section headers under
/// the active People / Updates / All inbox split (#295).
enum PeopleUpdatesListLayoutPolicy {
    static func usesDateSectionHeaders(
        showsPeopleUpdatesBar: Bool,
        activeTab: InboxSplitTab,
        groupByDate: Bool
    ) -> Bool {
        guard groupByDate else { return false }
        if showsPeopleUpdatesBar && activeTab == .updates {
            return false
        }
        return true
    }
}

/// Deterministic, local-only classifier for the People / Updates inbox split (ADR-0035 amendment).
enum PeopleUpdatesClassifier {
    private static let automatedLocalPartSubstrings = [
        "noreply",
        "no-reply",
        "donotreply",
        "do-not-reply",
        "mailer-daemon",
    ]

    private static let automatedExactLocalParts: Set<String> = [
        "notifications",
        "notification",
        "newsletter",
        "newsletters",
        "updates",
        "notices",
        "receipts",
        "billing",
        "marketing",
        "digest",
        "deployments",
        "deploy",
        "builds",
        "build",
        "ci",
        "alerts",
        "alert",
        "status",
        "releases",
        "release",
        "bot",
        "automated",
        "devops",
        "monitoring",
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
        "production deployment",
        "preview deployment",
        "deployment succeeded",
        "deployment failed",
        "deployment ready",
        "deploy succeeded",
        "deploy failed",
        "build succeeded",
        "build failed",
        "pipeline succeeded",
        "pipeline failed",
        "workflow run",
    ]

    private static func isAutomatedSenderEmail(_ senderEmail: String) -> Bool {
        let localPart = senderEmail.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        guard !localPart.isEmpty else { return false }
        if automatedLocalPartSubstrings.contains(where: { localPart.contains($0) }) {
            return true
        }
        let baseLocalPart = localPart.split(separator: "+", maxSplits: 1).first.map(String.init) ?? localPart
        return automatedExactLocalParts.contains(baseLocalPart)
    }

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

        if isAutomatedSenderEmail(senderEmail) {
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
        sourceID: MailSourceID?,
        effectiveDateOverrides: [MessageHeader.ID: Date] = [:]
    ) -> [UpdatesSenderBundle] {
        var grouped: [String: [MessageHeader]] = [:]
        var orderedKeys: [String] = []

        let sorted = headers.sorted { lhs, rhs in
            let lhsDate = effectiveDateOverrides[lhs.id] ?? lhs.date
            let rhsDate = effectiveDateOverrides[rhs.id] ?? rhs.date
            if lhsDate != rhsDate { return lhsDate > rhsDate }
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

    /// Returns strictly the individual message headers currently rendered as
    /// selectable rows in the Updates tab: single-message bundles and the
    /// children of expanded multi-message bundles (each message appears once,
    /// in exact rendered order, with no nested thread-child duplication) (#295).
    static func selectableHeaders(
        from headers: [MessageHeader],
        sourceID: MailSourceID?,
        expandedBundleIDs: Set<String>,
        effectiveDateOverrides: [MessageHeader.ID: Date] = [:]
    ) -> [MessageHeader] {
        let bundles = bundle(
            headers,
            sourceID: sourceID,
            effectiveDateOverrides: effectiveDateOverrides
        )
        var result: [MessageHeader] = []
        for entry in bundles where entry.headers.count == 1 || expandedBundleIDs.contains(entry.id) {
            result.append(contentsOf: entry.headers)
        }
        return result
    }

    /// Moves keyboard selection by a relative row delta across flat Updates rows,
    /// clearing any stale inline-child reader expansion preference while leaving
    /// bulk selection intact (#295).
    @MainActor
    static func applyKeyboardSelection(
        delta: Int,
        rows: [MessageHeader],
        navigation: MailNavigationState
    ) {
        guard !rows.isEmpty else { return }
        let target: MessageHeader
        if let currentID = navigation.selectedMessageID,
           let index = rows.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = min(max(0, index + delta), rows.count - 1)
            target = rows[nextIndex]
        } else {
            target = rows[0]
        }
        navigation.readerExpansionSelectionID = nil
        navigation.selectedMessageID = target.id
    }

    /// Moves keyboard selection for paging/home/end commands across flat Updates
    /// rows, clearing any stale inline-child reader expansion preference while
    /// leaving bulk selection intact (#295).
    @MainActor
    static func applyKeyboardSelection(
        command: MessageListKeyCommand,
        rows: [MessageHeader],
        navigation: MailNavigationState
    ) {
        let currentIndex = navigation.selectedMessageID.flatMap { id in
            rows.firstIndex(where: { $0.id == id })
        }
        guard let targetIndex = MessageListKeyboardNavigation.targetIndex(
            for: command,
            current: currentIndex,
            count: rows.count
        ) else { return }
        navigation.readerExpansionSelectionID = nil
        navigation.selectedMessageID = rows[targetIndex].id
    }
}
