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

@testable import BrevMail
import Foundation
import Testing

@Suite("ComposeLinkPolicy")
struct ComposeLinkPolicyTests {
    @Test("accepts http/https/mailto and normalizes bare forms")
    func accepts() {
        #expect(ComposeLinkPolicy.normalizedURL(from: "https://x.test")?.scheme == "https")
        #expect(ComposeLinkPolicy.normalizedURL(from: " example.com ")?.absoluteString == "https://example.com")
        #expect(ComposeLinkPolicy.normalizedURL(from: "a@b.test")?.scheme == "mailto")
    }

    @Test("rejects dangerous or empty schemes")
    func rejects() {
        #expect(ComposeLinkPolicy.normalizedURL(from: "javascript:alert(1)") == nil)
        #expect(ComposeLinkPolicy.normalizedURL(from: "data:text/html,x") == nil)
        #expect(ComposeLinkPolicy.normalizedURL(from: "   ") == nil)
    }
}
