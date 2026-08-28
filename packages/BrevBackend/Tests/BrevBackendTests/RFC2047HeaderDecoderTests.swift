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

@Suite("RFC 2047 header decoder")
struct RFC2047HeaderDecoderTests {
    // MARK: - Q-encoding (already partially tested via IMAP tests)

    @Test("decodes Q-encoded UTF-8 subject")
    func qEncodedUtf8() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?Q?Caf=C3=A9?=")
        #expect(result == "Café")
    }

    @Test("decodes Q-encoded with underscore as space")
    func qEncodedUnderscoreIsSpace() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?Q?Hello_World?=")
        #expect(result == "Hello World")
    }

    // MARK: - B-encoding (previously untested)

    @Test("decodes B-encoded UTF-8 subject")
    func bEncodedUtf8() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?B?SGVsbG8gV29ybGQ=?=")
        #expect(result == "Hello World")
    }

    @Test("decodes B-encoded ISO-8859-1 subject")
    func bEncodedLatin1() {
        let result = RFC2047HeaderDecoder.decode("=?ISO-8859-1?B?T2zp?=")
        #expect(result == "Olé")
    }

    @Test("decodes B-encoded with whitespace between encoded tokens")
    func bEncodedMultiTokenWithWhitespace() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?B?SGVsbG8=?= =?UTF-8?B?V29ybGQ=?=")
        #expect(result == "HelloWorld")
    }

    @Test("decodes B-encoded multi-token with non-whitespace between tokens")
    func bEncodedMultiTokenJoined() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?B?SGVs?=lo=?UTF-8?B?V29ybGQ=?=")
        #expect(result == "HelloWorld")
    }

    // MARK: - Edge cases

    @Test("passes through plain text unchanged")
    func plainText() {
        let result = RFC2047HeaderDecoder.decode("Hello World")
        #expect(result == "Hello World")
    }

    @Test("passes through truncated encoded token")
    func truncatedToken() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?Q?Truncat")
        #expect(result == "=?UTF-8?Q?Truncat")
    }

    @Test("skips unknown encoding")
    func unknownEncoding() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?X?SGVsbG8=?=")
        #expect(result == "=?UTF-8?X?SGVsbG8=?=")
    }

    @Test("handles mixed encoded and plain text")
    func mixedEncodedAndPlain() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?Q?Hello?= World")
        #expect(result == "Hello World")
    }

    @Test("decodes multiple consecutive encoded tokens")
    func multipleConsecutiveEncodedTokens() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?B?SGVsbG8=?==?UTF-8?B?V29ybGQ=?=")
        #expect(result == "HelloWorld")
    }

    @Test("handles B-encoded base64 with whitespace inside encoded text")
    func bEncodedWithInternalWhitespace() {
        let result = RFC2047HeaderDecoder.decode(
            "=?UTF-8?B?SGVsbG8g\r\n V29ybGQ=?="
        )
        #expect(result == "Hello World")
    }

    @Test("decodes Q-encoded with numeric hex values")
    func qEncodedNumericHex() {
        let result = RFC2047HeaderDecoder.decode("=?utf-8?Q?=31=2E=20Item?=")
        #expect(result == "1. Item")
    }

    @Test("tests uppercase encoding letter")
    func uppercaseEncodingLetter() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?Q?Test?=")
        #expect(result == "Test")
        let bResult = RFC2047HeaderDecoder.decode("=?UTF-8?B?VGVzdA==?=")
        #expect(bResult == "Test")
    }

    @Test("decodes empty encoded string")
    func emptyEncoded() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?Q??=")
        #expect(result == "")
    }

    @Test("handles B-encoded UTF-8 with multibyte characters")
    func bEncodedMultibyte() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?B?w6nDqMOow6k=?=")
        #expect(result == "éèèé")
    }

    @Test("handles non-UTF-8 B-encoded data with charset fallback")
    func bEncodedWindows1252() {
        let result = RFC2047HeaderDecoder.decode("=?windows-1252?B?g4SG?=")
        #expect(result == "ƒ„†")
    }

    @Test("handles plain text before encoded token")
    func plainBeforeEncoded() {
        let result = RFC2047HeaderDecoder.decode("Re: =?UTF-8?Q?Hello?=")
        #expect(result == "Re: Hello")
    }

    @Test("handles encoded token at start with plain text after")
    func encodedBeforePlain() {
        let result = RFC2047HeaderDecoder.decode("=?UTF-8?Q?Hello?= World!")
        #expect(result == "Hello World!")
    }

    // MARK: - Charset coverage beyond the hardcoded fast path

    @Test("strips an RFC 2231 *language suffix from the charset") func charsetLanguageSuffix() {
        // Same bytes as the ISO-8859-1 case, but with a "*en" language tag that
        // previously made the charset fall through to a UTF-8 mis-decode.
        let result = RFC2047HeaderDecoder.decode("=?ISO-8859-1*en?B?T2zp?=")
        #expect(result == "Olé")
    }

    @Test("decodes ISO-8859-15 (latin-9) Euro sign via the IANA registry")
    func isoLatin9EuroSign() {
        // ISO-8859-15 differs from -1 at 0xA4, where it places the Euro sign.
        let result = RFC2047HeaderDecoder.decode("=?ISO-8859-15?Q?=A4?=")
        #expect(result == "€")
    }

    @Test("decodes windows-1251 Cyrillic via the IANA registry") func windows1251Cyrillic() {
        // windows-1251 0xC0 is CYRILLIC CAPITAL LETTER A.
        let result = RFC2047HeaderDecoder.decode("=?windows-1251?Q?=C0?=")
        #expect(result == "А")
    }

    @Test("decodes KOI8-R Cyrillic via the IANA registry") func koi8rCyrillic() {
        // KOI8-R 0xF0 is CYRILLIC CAPITAL LETTER PE.
        let result = RFC2047HeaderDecoder.decode("=?KOI8-R?Q?=F0?=")
        #expect(result == "П")
    }
}
