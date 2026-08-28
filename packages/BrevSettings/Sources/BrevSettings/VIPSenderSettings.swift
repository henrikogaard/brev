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

/// A single VIP sender entry. Keyed by normalized (lowercased) email.
///
/// VIP state is always local-only. Provider sync is a v2 concern and
/// must be capability-gated; it is not part of this model.
public struct VIPSender: Codable, Equatable, Sendable, Identifiable {
    /// Normalized lowercase email address. Used as the stable key.
    public let email: String
    /// Optional human-readable display name (from Contacts or the message header).
    public var displayName: String?
    /// Date the sender was marked as VIP.
    public let addedAt: Date

    public var id: String { email }

    public init(email: String, displayName: String? = nil, addedAt: Date = Date()) {
        self.email = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName
        self.addedAt = addedAt
    }
}

/// Persisted store for the local VIP sender list.
public struct VIPSenderSettings: Codable, Equatable, Sendable {
    public enum Key {
        public static let senders = "vip.senders"
    }

    public var senders: [VIPSender]

    public static let defaults = VIPSenderSettings(senders: [])

    public init(senders: [VIPSender]) {
        self.senders = senders
    }

    public static func load(from defaults: UserDefaults = .standard) -> VIPSenderSettings {
        guard let data = defaults.data(forKey: Key.senders),
              let settings = try? JSONDecoder().decode(VIPSenderSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Key.senders)
    }

    /// Returns `true` when the given email is a VIP sender.
    public func isVIP(email: String) -> Bool {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return senders.contains { $0.email == normalized }
    }

    /// Adds a VIP sender. Silently deduplicates by email.
    public mutating func add(_ sender: VIPSender) {
        let normalized = sender.email
        guard !senders.contains(where: { $0.email == normalized }) else { return }
        senders.append(sender)
    }

    /// Removes the VIP sender with the given email, if present.
    public mutating func remove(email: String) {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        senders.removeAll { $0.email == normalized }
    }
}
