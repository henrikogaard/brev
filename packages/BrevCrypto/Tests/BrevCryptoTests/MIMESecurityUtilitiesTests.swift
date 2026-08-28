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

@testable import BrevCrypto
import Foundation
import Testing

@Suite("MIME security utilities")
struct MIMESecurityUtilitiesTests {
    @Test("splitting preserves non-UTF-8 body bytes exactly")
    func splittingPreservesNonUTF8BodyBytes() {
        let header = Data("Subject: Binary\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        let body = Data([0x00, 0xFF, 0x80, 0x0A, 0x0D, 0x41])

        let split = MIMEEntitySplit.make(from: header + body)

        #expect(split.topHeaderLines == ["Subject: Binary"])
        #expect(split.contentEntity.suffix(body.count) == body)
    }
}
