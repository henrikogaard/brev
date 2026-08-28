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

@Suite("MailPrintDocument body preference")
struct MailPrintDocumentBodyPreferenceTests {
    @Test("prefers HTML body content when both HTML and plain exist")
    func prefersHTMLWhenBothExist() {
        let body = MessageBody(
            messageID: "m1",
            html: "<p>HTML_ONLY_MARKER</p>",
            plainText: "PLAIN_ONLY_MARKER"
        )
        let text = MailPrintDocument.bodyText(body)
        #expect(text.contains("HTML_ONLY_MARKER"))
        #expect(!text.contains("PLAIN_ONLY_MARKER"))
    }

    @Test("falls back to plain when HTML missing")
    func fallsBackToPlain() {
        let body = MessageBody(messageID: "m2", plainText: "just plain")
        #expect(MailPrintDocument.bodyText(body) == "just plain")
    }
}
