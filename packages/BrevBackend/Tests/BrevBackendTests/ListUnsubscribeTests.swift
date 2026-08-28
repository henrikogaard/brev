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

@Suite("List-Unsubscribe")
struct ListUnsubscribeTests {
    @Test("parser keeps HTTPS and mailto methods in header order")
    func parserKeepsHTTPSAndMailtoMethodsInHeaderOrder() throws {
        let options = ListUnsubscribeOptions.parse(
            listUnsubscribe: """
            <https://lists.example.org/unsubscribe?id=123>, \
            <mailto:unsubscribe@example.org?subject=unsubscribe>
            """,
            listUnsubscribePost: "List-Unsubscribe=One-Click"
        )

        #expect(options.methods == [
            .https(URL(string: "https://lists.example.org/unsubscribe?id=123")!, supportsOneClick: true),
            .mailto(URL(string: "mailto:unsubscribe@example.org?subject=unsubscribe")!)
        ])
        #expect(options.requiresExplicitConfirmation)
    }

    @Test("parser rejects unsafe schemes")
    func parserRejectsUnsafeSchemes() {
        let options = ListUnsubscribeOptions.parse(
            listUnsubscribe: "<javascript:alert(1)>, <ftp://example.org/unsubscribe>",
            listUnsubscribePost: nil
        )

        #expect(options.methods.isEmpty)
    }

    @Test("parser rejects suspicious HTTPS and malformed mailto methods")
    func parserRejectsSuspiciousHTTPSAndMalformedMailtoMethods() {
        let options = ListUnsubscribeOptions.parse(
            listUnsubscribe: "<https://user:token@example.org/unsubscribe>, <mailto:not-an-address>, <mailto:unsafe%20address@example.org>",
            listUnsubscribePost: nil
        )

        #expect(options.methods.isEmpty)
    }
}
