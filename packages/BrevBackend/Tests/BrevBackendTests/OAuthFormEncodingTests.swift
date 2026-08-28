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

@Suite("OAuthFormEncoding")
struct OAuthFormEncodingTests {
    private func encoded(_ items: [String: String]) -> String {
        String(decoding: OAuthFormEncoding.encode(items), as: UTF8.self)
    }

    @Test("percent-encodes +, /, =, and space (which a form parser would otherwise mangle)")
    func encodesReservedFormCharacters() {
        // A Microsoft-style refresh token: standard-base64 alphabet, so it
        // routinely contains + and /. With the old URLComponents encoder the +
        // passed through literally and the server decoded it as a space →
        // invalid_grant on every refresh.
        let body = encoded(["refresh_token": "M.C5+a/bQ8=="])
        #expect(body == "refresh_token=M.C5%2Ba%2FbQ8%3D%3D")
        #expect(!body.contains("+"))
        #expect(!body.contains("/"))

        #expect(encoded(["k": "a b"]) == "k=a%20b") // space, never bare +
    }

    @Test("a token with + round-trips back to its original value")
    func roundTripsThroughFormDecoding() throws {
        let original = "M.C5+a/bQ8=="
        let body = encoded(["refresh_token": original])
        // Split off the value and percent-decode it the way a server would.
        let value = try #require(body.split(separator: "=", maxSplits: 1).last.map(String.init))
        #expect(value.removingPercentEncoding == original)
    }

    @Test("keys are emitted in sorted order for a deterministic body")
    func deterministicKeyOrder() {
        let body = encoded([
            "refresh_token": "tok",
            "grant_type": "refresh_token",
            "client_id": "abc",
        ])
        #expect(body == "client_id=abc&grant_type=refresh_token&refresh_token=tok")
    }
}
