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

@Suite("MessageRawSourcePresentation")
struct MessageRawSourcePresentationTests {
    private static let crlfMessage = "From: a@example.org\r\nSubject: Hi\r\n\r\nBody line one\r\nBody line two\r\n"
    private static let lfMessage = "From: a@example.org\nSubject: Hi\n\nBody line one\n"

    @Test("full source returns the whole message, normalised to LF")
    func fullSourceReturnsEverything() {
        let body = MessageRawSourcePresentation.body(from: Self.crlfMessage, mode: .fullSource)
        #expect(body == "From: a@example.org\nSubject: Hi\n\nBody line one\nBody line two\n")
    }

    @Test("headers-only stops at the first blank line (CRLF separator)")
    func headersOnlyStopsAtBlankLineCRLF() {
        let body = MessageRawSourcePresentation.body(from: Self.crlfMessage, mode: .headersOnly)
        #expect(body == "From: a@example.org\nSubject: Hi")
    }

    @Test("headers-only stops at the first blank line (LF separator)")
    func headersOnlyStopsAtBlankLineLF() {
        let body = MessageRawSourcePresentation.body(from: Self.lfMessage, mode: .headersOnly)
        #expect(body == "From: a@example.org\nSubject: Hi")
    }

    @Test("headers-only returns the whole input when there is no blank-line separator")
    func headersOnlyWithoutSeparatorReturnsInput() {
        let headersOnly = "From: a@example.org\r\nSubject: Hi\r\n"
        let body = MessageRawSourcePresentation.body(from: headersOnly, mode: .headersOnly)
        #expect(body == "From: a@example.org\nSubject: Hi\n")
    }
}
