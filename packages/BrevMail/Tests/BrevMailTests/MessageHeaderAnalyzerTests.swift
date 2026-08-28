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

import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageHeaderAnalyzer")
struct MessageHeaderAnalyzerTests {
    @Test("DMARC fail and permerror are flagged; pass and transient temperror are not")
    func dmarcFailureDetection() {
        #expect(MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; dmarc=fail header.from=evil.test"))
        // permerror (malformed/unevaluable DMARC) was previously missed.
        #expect(MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; spf=pass; dmarc=permerror"))
        #expect(!MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; dmarc=pass"))
        // temperror is a transient DNS condition, not a spoof signal.
        #expect(!MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; dmarc=temperror"))
        #expect(!MessageHeaderAnalyzer.hasDMARCFail(in: nil))
    }
}
