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

import CryptoKit
import Foundation

// MARK: - PKCE (RFC 7636)

/// A Proof Key for Code Exchange (PKCE, RFC 7636) verifier/challenge pair.
///
/// Generated when an authorization URL is built and carried through to the
/// matching token exchange so the authorization server can bind the code to
/// the client that requested it. Used by both `GoogleOAuthFlow` and
/// `OutlookOAuthFlow` because Brev's OAuth clients are public clients.
struct PKCECodePair: Sendable, Equatable {
    /// The high-entropy `code_verifier`: 32 random bytes, base64url-encoded
    /// without padding.
    let verifier: String
    /// The `code_challenge`: `base64url(SHA256(verifier))`, sent with
    /// `code_challenge_method=S256`.
    let challenge: String

    /// Creates a fresh pair from 32 cryptographically random bytes.
    init() {
        let verifier = Self.randomVerifier()
        self.init(verifier: verifier)
    }

    /// Creates a pair from a known verifier, deriving the challenge. Exposed
    /// for tests that need a deterministic verifier.
    init(verifier: String) {
        self.verifier = verifier
        challenge = Self.challenge(for: verifier)
    }

    /// Generates a base64url-encoded `code_verifier` from 32 random bytes.
    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fall back to the system RNG if SecRandomCopyBytes is unavailable;
            // both are CSPRNGs, so either is acceptable for a code_verifier.
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = generator.next()
            }
        }
        return base64URLEncode(Data(bytes))
    }

    /// Computes `base64url(SHA256(verifier))` per RFC 7636 S256.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Base64url encoding without padding, per RFC 7636 Appendix A.
    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
