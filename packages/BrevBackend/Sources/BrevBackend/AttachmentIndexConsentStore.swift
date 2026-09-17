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

/// Per-account opt-in store for local attachment content indexing (ADR-0078 §1).
///
/// The flag defaults to `false` and is reversible. It is deliberately kept out
/// of the ADR-0076 settings backup: indexing consent is device-local state and
/// must never silently re-enable on another machine. Revocation semantics
/// (remove all indexed rows, stop the indexer) are enforced by the owning
/// backend's `AttachmentIndexer`, which consults `isEnabled(accountID:)`
/// before every unit of work.
public final class AttachmentIndexConsentStore: @unchecked Sendable {
    /// Shared store over the standard user defaults.
    public static let shared = AttachmentIndexConsentStore()

    /// Posted on `NotificationCenter.default` when a per-account flag changes.
    /// `userInfo["accountID"]` carries the account ID.
    public static let didChangeNotification = Notification.Name("AttachmentIndexConsentDidChange")

    private static let keyPrefix = "mail.attachmentContentIndexingEnabled."

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    /// Whether attachment content indexing is enabled for the account;
    /// false when unset.
    public func isEnabled(accountID: BrevAccount.ID) -> Bool {
        defaults.bool(forKey: Self.key(for: accountID))
    }

    /// Records or revokes the consent and posts `didChangeNotification`.
    public func setEnabled(_ isEnabled: Bool, accountID: BrevAccount.ID) {
        defaults.set(isEnabled, forKey: Self.key(for: accountID))
        notificationCenter.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: ["accountID": accountID]
        )
    }

    /// Clears the stored flag, for account removal. Also notifies listeners so
    /// a live indexer stops and purges its rows.
    public func revokeConsent(accountID: BrevAccount.ID) {
        defaults.removeObject(forKey: Self.key(for: accountID))
        notificationCenter.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: ["accountID": accountID]
        )
    }

    private static func key(for accountID: BrevAccount.ID) -> String {
        keyPrefix + accountID
    }
}
