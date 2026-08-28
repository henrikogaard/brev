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

@testable import BrevCalendar
import Foundation
import Testing

@Suite("vCard value unescaping")
struct VCardParsingTests {
    @Test("unescapes the RFC 6350 escapes") func basicEscapes() {
        #expect(VCardXMLParser.unescapeVCardValue("line\\none") == "line\none") // \n → newline
        #expect(VCardXMLParser.unescapeVCardValue("a\\,b") == "a,b") // \, → comma
        #expect(VCardXMLParser.unescapeVCardValue("a\\;b") == "a;b") // \; → semicolon
        #expect(VCardXMLParser.unescapeVCardValue("a\\\\b") == "a\\b") // \\ → backslash
    }

    @Test("an escaped backslash before n stays backslash + n (single-pass, not a newline)")
    func escapedBackslashBeforeN() {
        // vCard "\\n" = escaped backslash + literal "n" = `\` + "n". A naive
        // sequence that unescapes "\\" last would turn it into `\` + newline.
        #expect(VCardXMLParser.unescapeVCardValue("\\\\n") == "\\n")
        // And an escaped backslash before a comma: `\` + ","
        #expect(VCardXMLParser.unescapeVCardValue("\\\\,") == "\\,")
    }

    @Test("an unknown escape keeps both characters verbatim") func unknownEscape() {
        #expect(VCardXMLParser.unescapeVCardValue("a\\qb") == "a\\qb")
    }
}
