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

@testable import BrevBackend
import Foundation
import Testing

@Suite("RemoteContentPolicy")
struct RemoteContentPolicyTests {
    @Test("default policy blocks sender and domain remote content")
    func defaultPolicyBlocksSenderAndDomainRemoteContent() throws {
        let defaults = try Self.makeDefaults()

        let policy = RemoteContentPolicy.load(from: defaults)

        #expect(!policy.allows(senderEmail: "alice@example.com", resourceHost: "example.com"))
    }

    @Test("allowlists normalize sender and domain values")
    func allowlistsNormalizeSenderAndDomainValues() {
        var policy = RemoteContentPolicy.defaults

        policy.allow(senderEmail: "  ALICE@Example.COM ")
        policy.allow(domain: " CDN.Example.COM ")

        #expect(policy.allowedSenderEntries == ["alice@example.com"])
        #expect(policy.allowedDomainEntries == ["cdn.example.com"])
        #expect(policy.hasAllowlistEntries)
        #expect(policy.allows(senderEmail: "alice@example.com", resourceHost: nil))
        #expect(policy.allows(senderEmail: "updates@cdn.example.com", resourceHost: "tracker.example.net"))
        #expect(policy.allows(senderEmail: "someone@else.com", resourceHost: "cdn.example.com"))
        #expect(!policy.allows(senderEmail: "someone@else.com", resourceHost: "tracking.example.net"))
    }

    @Test("allowlist entries can be revoked by normalized sender or domain")
    func allowlistEntriesCanBeRevokedByNormalizedSenderOrDomain() {
        var policy = RemoteContentPolicy.defaults
        policy.allow(senderEmail: "alice@example.com")
        policy.allow(domain: "example.com")

        policy.revoke(senderEmail: " ALICE@EXAMPLE.COM ")
        policy.revoke(domain: "https://example.com/assets/pixel.png")

        #expect(policy.allowedSenderEntries == [])
        #expect(policy.allowedDomainEntries == [])
        #expect(policy.hasAllowlistEntries == false)
        #expect(!policy.allows(senderEmail: "alice@example.com", resourceHost: "example.com"))
    }

    @Test("saving and loading preserves allowlists")
    func savingAndLoadingPreservesAllowlists() throws {
        let defaults = try Self.makeDefaults()
        var policy = RemoteContentPolicy.defaults
        policy.allow(senderEmail: "alice@example.com")
        policy.allow(domain: "example.com")

        policy.save(to: defaults)
        let restored = RemoteContentPolicy.load(from: defaults)

        #expect(restored == policy)
    }

    @Test("corrupt persisted allowlist data falls back to defaults")
    func corruptPersistedAllowlistDataFallsBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: RemoteContentPolicy.storageKey)

        let policy = RemoteContentPolicy.load(from: defaults)

        #expect(policy == .defaults)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "RemoteContentPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
