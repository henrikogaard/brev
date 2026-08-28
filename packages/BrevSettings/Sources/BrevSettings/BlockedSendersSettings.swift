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

/// Local storage for addresses the user has manually blocked in Brev.
///
/// This is a *client-side* blocklist stored in `UserDefaults`. It is distinct
/// from the server-side block action exposed by `BackendCapabilities.blockSender`.
/// When the server-side capability is present Brev uses both: the backend
/// prevents future delivery while this list suppresses display of any
/// already-synced messages from the blocked address.
public struct BlockedSendersSettings: Codable, Equatable, Sendable {
    public enum Key {
        public static let blockedEmails = "blockedSenders.emails"
    }

    public var blockedEmails: [String]

    public static let defaults = BlockedSendersSettings(blockedEmails: [])

    public init(blockedEmails: [String] = []) {
        self.blockedEmails = blockedEmails
    }

    // MARK: - Persistence

    public static func load(from defaults: UserDefaults = .standard) -> BlockedSendersSettings {
        guard let data = defaults.data(forKey: Key.blockedEmails),
              let settings = try? JSONDecoder().decode(BlockedSendersSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Key.blockedEmails)
    }

    // MARK: - Queries

    /// Returns `true` when `email` is in the local blocklist (case-insensitive).
    public func isBlocked(_ email: String) -> Bool {
        let normalized = email.lowercased()
        return blockedEmails.contains { $0.lowercased() == normalized }
    }

    // MARK: - Mutations

    /// Adds `email` to the blocklist if it is not already present.
    public mutating func block(_ email: String) {
        let normalized = email.lowercased()
        guard !blockedEmails.contains(where: { $0.lowercased() == normalized }) else { return }
        blockedEmails.append(email)
    }

    /// Removes `email` from the blocklist.
    public mutating func unblock(_ email: String) {
        let normalized = email.lowercased()
        blockedEmails.removeAll { $0.lowercased() == normalized }
    }
}
