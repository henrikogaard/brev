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
import Foundation

/// Local, per-message "keep offline" pins (#268, ADR-0034). A pinned message's
/// cached body is exempted from retention eviction. Scoped by
/// account|mailbox|messageID so the same UID in two accounts can't collide
/// (the Unified Inbox shows several sources at once). Local-only for now;
/// cross-device sync is deferred to the provider-workflow-state work (#261).
struct MessageOfflineRetentionOverrideStore: Equatable {
    static let empty = MessageOfflineRetentionOverrideStore(defaults: emptyDefaults)

    private static let key = "list.offlineRetentionOverrides"
    private static let emptyDefaults = UserDefaults(
        suiteName: "MessageOfflineRetentionOverrideStore.empty"
    ) ?? .standard
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func == (
        lhs: MessageOfflineRetentionOverrideStore,
        rhs: MessageOfflineRetentionOverrideStore
    ) -> Bool {
        lhs.defaults === rhs.defaults
    }

    func isKeptOffline(_ messageID: SourceMessageID) -> Bool {
        pins().contains(Self.storageKey(for: messageID))
    }

    /// Toggles a pin. This is a read-modify-write of the whole pin array, so it
    /// must be called from a single serial context — in practice all callers are
    /// `@MainActor` SwiftUI handlers, which serializes concurrent toggles. If a
    /// non-main-actor writer is ever added, move the set to an actor to avoid a
    /// lost update.
    func setKeptOffline(_ kept: Bool, for messageID: SourceMessageID) {
        var stored = pins()
        let key = Self.storageKey(for: messageID)
        if kept { stored.insert(key) } else { stored.remove(key) }
        defaults.set(Array(stored), forKey: Self.key)
    }

    /// The bare message IDs pinned within an account, for handing to the
    /// per-folder retention sweep so they are never evicted. Matched by
    /// *account* (not account+mailbox): the sweep keys folders by the backend's
    /// source whose `mailboxID` need not equal the `mailboxID` recorded when the
    /// pin was written (e.g. the local-workflow `accountID|accountID` fallback
    /// used by smart views). Over-returning a pin to another of the account's
    /// folders is harmless — the per-folder eviction only matches that folder's
    /// own message IDs. Components are split on the first two `|`, so a `|` in
    /// the messageID is preserved.
    func keptOfflineMessageIDs(forSource sourceID: MailSourceID) -> Set<MessageHeader.ID> {
        Set(
            pins().compactMap { key in
                let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3, String(parts[0]) == sourceID.accountID else { return nil }
                return String(parts[2])
            }
        )
    }

    private func pins() -> Set<String> {
        Set(defaults.array(forKey: Self.key) as? [String] ?? [])
    }

    private static func storageKey(for messageID: SourceMessageID) -> String {
        "\(messageID.sourceID.accountID)|\(messageID.sourceID.mailboxID)|\(messageID.messageID)"
    }
}
