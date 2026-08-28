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

public struct RemoteContentPolicy: Codable, Equatable, Sendable {
    public static let storageKey = "privacy.remoteContentPolicy"

    private var allowedSenders: Set<String>
    private var allowedDomains: Set<String>

    public var allowedSenderEntries: [String] {
        allowedSenders.sorted()
    }

    public var allowedDomainEntries: [String] {
        allowedDomains.sorted()
    }

    public var hasAllowlistEntries: Bool {
        !allowedSenders.isEmpty || !allowedDomains.isEmpty
    }

    public static let defaults = RemoteContentPolicy(
        allowedSenders: [],
        allowedDomains: []
    )

    public static func load(from defaults: UserDefaults = .standard) -> RemoteContentPolicy {
        guard let data = defaults.data(forKey: storageKey),
              let policy = try? JSONDecoder().decode(RemoteContentPolicy.self, from: data) else {
            return .defaults
        }
        return policy
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public mutating func allow(senderEmail: String) {
        guard let sender = Self.normalizedEmail(senderEmail) else { return }
        allowedSenders.insert(sender)
    }

    public mutating func allow(domain: String) {
        guard let domain = Self.normalizedDomain(domain) else { return }
        allowedDomains.insert(domain)
    }

    public mutating func revoke(senderEmail: String) {
        guard let sender = Self.normalizedEmail(senderEmail) else { return }
        allowedSenders.remove(sender)
    }

    public mutating func revoke(domain: String) {
        guard let domain = Self.normalizedDomain(domain) else { return }
        allowedDomains.remove(domain)
    }

    public func allows(senderEmail: String, resourceHost: String?) -> Bool {
        if let sender = Self.normalizedEmail(senderEmail),
           allowedSenders.contains(sender) {
            return true
        }

        if let senderDomain = Self.senderDomain(for: senderEmail),
           Self.domain(senderDomain, matchesAny: allowedDomains) {
            return true
        }

        guard let resourceDomain = Self.normalizedDomain(resourceHost) else {
            return false
        }

        return Self.domain(resourceDomain, matchesAny: allowedDomains)
    }

    public static func senderDomain(for email: String) -> String? {
        guard let sender = normalizedEmail(email),
              let atIndex = sender.lastIndex(of: "@") else {
            return nil
        }
        return normalizedDomain(String(sender[sender.index(after: atIndex)...]))
    }

    private static func normalizedEmail(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.contains("@"), !normalized.hasPrefix("@"), !normalized.hasSuffix("@") else {
            return nil
        }
        return normalized
    }

    private static func normalizedDomain(_ value: String?) -> String? {
        guard var normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty else {
            return nil
        }

        if normalized.contains("://"),
           let host = URLComponents(string: normalized)?.host {
            normalized = host
        }

        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func domain(_ domain: String, matchesAny allowedDomains: Set<String>) -> Bool {
        allowedDomains.contains { allowedDomain in
            domain == allowedDomain || domain.hasSuffix(".\(allowedDomain)")
        }
    }
}
