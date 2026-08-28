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

@Suite("MIMECharset")
struct MIMECharsetTests {
    @Test("recognizedEncoding resolves common charsets")
    func recognizedCommonCharsets() {
        #expect(MIMECharset.recognizedEncoding(for: "utf-8") == .utf8)
        #expect(MIMECharset.recognizedEncoding(for: "US-ASCII") == .ascii)
        #expect(MIMECharset.recognizedEncoding(for: "iso-8859-1") == .isoLatin1)
        #expect(MIMECharset.recognizedEncoding(for: "windows-1252") == .windowsCP1252)
    }

    @Test("recognizedEncoding resolves registry charsets")
    func recognizedRegistryCharset() {
        #expect(MIMECharset.recognizedEncoding(for: "iso-8859-15") != nil)
    }

    @Test("recognizedEncoding returns nil for an unknown charset")
    func recognizedUnknownIsNil() {
        #expect(MIMECharset.recognizedEncoding(for: "x-not-a-real-charset") == nil)
    }

    @Test("encoding defaults an unknown charset to UTF-8")
    func encodingDefaultsUnknownToUTF8() {
        #expect(MIMECharset.encoding(for: "x-not-a-real-charset") == .utf8)
    }

    @Test("RFC 2231 language suffix is stripped before matching")
    func stripsLanguageSuffix() {
        #expect(MIMECharset.recognizedEncoding(for: "utf-8*en") == .utf8)
    }
}
