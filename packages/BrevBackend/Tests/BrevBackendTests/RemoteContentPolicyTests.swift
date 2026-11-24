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

    @Test("trusted-sender evaluator matches normalized local contacts and replied-to addresses")
    func trustedSenderEvaluatorMatchesNormalizedContactsAndRepliedTo() {
        let evaluator = TrustedSenderEvaluator(
            contactEmails: ["  Alice@Example.COM ", "not-an-email", ""],
            repliedToEmails: ["Bob@Work.Org\n", "@bad.example", "bad@"]
        )

        #expect(evaluator.trustSource(for: "alice@example.com") == .localContacts)
        #expect(evaluator.trustSource(for: "  ALICE@example.com  ") == .localContacts)
        #expect(evaluator.isTrusted(senderEmail: "alice@example.com"))

        #expect(evaluator.trustSource(for: "bob@work.org") == .repliedToSender)
        #expect(evaluator.trustSource(for: "BOB@WORK.ORG") == .repliedToSender)
        #expect(evaluator.isTrusted(senderEmail: "bob@work.org"))
    }

    @Test("trusted-sender evaluator rejects unknown senders, domain-only matches, and malformed addresses")
    func trustedSenderEvaluatorRejectsUnknownDomainOnlyAndMalformed() {
        let evaluator = TrustedSenderEvaluator(
            contactEmails: ["alice@example.com"],
            repliedToEmails: ["bob@work.org"]
        )

        #expect(!evaluator.isTrusted(senderEmail: "stranger@other.net"))
        // Domain-only match must NOT qualify as trusted unless domain-allowlisted.
        #expect(!evaluator.isTrusted(senderEmail: "carol@example.com"))
        #expect(!evaluator.isTrusted(senderEmail: "dave@work.org"))

        // Empty and malformed addresses must never match.
        for malformed in [
            "",
            "   ",
            "not-an-email",
            "@example.com",
            "alice@",
            "a@b@example.com",
            "alice @example.com",
            "alice@.example.com",
            "alice@example.",
            "alice@localhost"
        ] {
            #expect(!evaluator.isTrusted(senderEmail: malformed), "unexpected match for \(malformed)")
            #expect(TrustedSenderEvaluator.normalizedEmail(malformed) == nil)
        }
    }

    @Test("remote content policy honors trusted-sender opt-in and domain allowlist independently")
    func remoteContentPolicyHonorsTrustedSenderOptInAndDomainAllowlist() {
        let evaluator = TrustedSenderEvaluator(
            contactEmails: ["alice@example.com"],
            repliedToEmails: ["bob@work.org"]
        )
        let defaultPolicy = RemoteContentPolicy.defaults

        // Toggle OFF: trusted sender stays blocked.
        #expect(!defaultPolicy.allows(
            senderEmail: "alice@example.com",
            resourceHost: "cdn.example.net",
            allowTrustedSenders: false,
            trustedSenders: evaluator
        ))
        // Toggle ON: exact trusted contact or replied-to sender is allowed.
        #expect(defaultPolicy.allows(
            senderEmail: "ALICE@EXAMPLE.COM",
            resourceHost: "cdn.example.net",
            allowTrustedSenders: true,
            trustedSenders: evaluator
        ))
        #expect(defaultPolicy.allows(
            senderEmail: "bob@work.org",
            resourceHost: "cdn.example.net",
            allowTrustedSenders: true,
            trustedSenders: evaluator
        ))
        // Toggle ON: same domain but different address is still blocked without a domain allowlist.
        #expect(!defaultPolicy.allows(
            senderEmail: "carol@example.com",
            resourceHost: "cdn.example.net",
            allowTrustedSenders: true,
            trustedSenders: evaluator
        ))

        // Domain allowlist still permits other addresses on that domain even when trusted-sender tier is off.
        var domainPolicy = RemoteContentPolicy.defaults
        domainPolicy.allow(domain: "example.com")
        #expect(domainPolicy.allows(
            senderEmail: "carol@example.com",
            resourceHost: "cdn.example.net",
            allowTrustedSenders: false,
            trustedSenders: evaluator
        ))
    }

    @Test("failed sender authentication blocks trusted-sender trust even for matching contacts and replied-to senders")
    func failedSenderAuthenticationBlocksTrustedSenderTrust() {
        let evaluator = TrustedSenderEvaluator(
            contactEmails: ["alice@example.com"],
            repliedToEmails: ["bob@work.org"]
        )

        #expect(evaluator.trustSource(for: "alice@example.com", senderAuthenticationFailed: true) == nil)
        #expect(!evaluator.isTrusted(senderEmail: "alice@example.com", senderAuthenticationFailed: true))
        #expect(evaluator.trustSource(for: "bob@work.org", senderAuthenticationFailed: true) == nil)
        #expect(!evaluator.isTrusted(senderEmail: "bob@work.org", senderAuthenticationFailed: true))
        #expect(!RemoteContentPolicy.defaults.allows(
            senderEmail: "alice@example.com",
            resourceHost: "cdn.example.net",
            allowTrustedSenders: true,
            trustedSenders: evaluator,
            senderAuthenticationFailed: true
        ))
    }

    @Test("saving a remote content policy posts didChangeNotification for open readers")
    func savingPolicyPostsChangeNotification() throws {
        let defaults = try Self.makeDefaults()
        var receivedDefaults: UserDefaults?
        let token = NotificationCenter.default.addObserver(
            forName: RemoteContentPolicy.didChangeNotification,
            object: defaults,
            queue: nil
        ) { notification in
            receivedDefaults = notification.object as? UserDefaults
        }
        defer { NotificationCenter.default.removeObserver(token) }

        var policy = RemoteContentPolicy.defaults
        policy.allow(senderEmail: "alice@example.com")
        policy.save(to: defaults)

        #expect(receivedDefaults === defaults)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "RemoteContentPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
