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

import Foundation

/// Read-side consent boundary for remote related-header discovery (ADR-0074,
/// ADR-0006). Provider backends consult this before any remote lookup; the
/// flag being false must make remote discovery impossible, not merely hidden.
public protocol RelatedConversationConsenting: Sendable {
    /// Returns whether remote related-header loading is currently consented for the account.
    func isRelatedConversationConsented(accountID: BrevAccount.ID) async -> Bool
}

/// Per-account consent store for remote related-header discovery.
///
/// Two consent surfaces feed the same check (ADR-0074 §6):
/// - The reader's explicit **Load related mail** action records an in-memory
///   session consent that never survives relaunch and never enables background
///   work by itself.
/// - A persistent per-account preference, defaulting off and reversible in
///   Mailbox View settings, additionally allows automatic lookups when a
///   conversation opens.
///
/// Revocation clears both surfaces. Account removal must call
/// `revokeConsent(accountID:)` so a replacement account never inherits it.
public final class RelatedConversationConsentStore: RelatedConversationConsenting, @unchecked Sendable {
    /// Shared store over the standard user defaults; app wiring passes this to
    /// both provider backends and the reader.
    public static let shared = RelatedConversationConsentStore()

    private static let autoLoadKeyPrefix = "conversation.relatedMailAutoLoad."

    /// Session grants are process-wide, not per store instance — account
    /// removal paths construct a fresh store over the same defaults and must
    /// still clear a grant made through `.shared`.
    private static let sessionLock = NSLock()
    private static var sessionConsents: Set<BrevAccount.ID> = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Persistent per-account automatic-lookup consent; false when unset.
    public func isAutoLoadEnabled(accountID: BrevAccount.ID) -> Bool {
        defaults.bool(forKey: Self.key(for: accountID))
    }

    /// The subset of `accountIDs` with persistent auto-load consent enabled.
    /// Used by settings backup export (ADR-0076), which only knows the
    /// accounts it is writing.
    public func autoLoadEnabledAccountIDs(among accountIDs: [BrevAccount.ID]) -> [BrevAccount.ID] {
        accountIDs.filter { isAutoLoadEnabled(accountID: $0) }
    }

    /// Records or revokes the persistent automatic-lookup consent. Revoking also
    /// drops any session consent granted earlier.
    public func setAutoLoadEnabled(_ isEnabled: Bool, accountID: BrevAccount.ID) {
        defaults.set(isEnabled, forKey: Self.key(for: accountID))
        if !isEnabled {
            Self.sessionLock.withLock { _ = Self.sessionConsents.remove(accountID) }
        }
    }

    /// Records consent for this app session only — used by the explicit
    /// Load related mail action so one tap never becomes a stored preference.
    public func grantForSession(accountID: BrevAccount.ID) {
        Self.sessionLock.withLock { _ = Self.sessionConsents.insert(accountID) }
    }

    /// Clears persistent and session consent, for account removal or revocation.
    public func revokeConsent(accountID: BrevAccount.ID) {
        defaults.removeObject(forKey: Self.key(for: accountID))
        Self.sessionLock.withLock { _ = Self.sessionConsents.remove(accountID) }
    }

    /// True when either the session grant or the persisted preference authorizes
    /// a remote related-header lookup for this account right now.
    public func isRelatedConversationConsented(accountID: BrevAccount.ID) async -> Bool {
        if Self.sessionLock.withLock({ Self.sessionConsents.contains(accountID) }) { return true }
        return isAutoLoadEnabled(accountID: accountID)
    }

    private static func key(for accountID: BrevAccount.ID) -> String {
        autoLoadKeyPrefix + accountID
    }
}
